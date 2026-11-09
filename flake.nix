{
  description = "A NixOS-based distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, disko, ... }:
    let
      # Einzige Stelle mit der Versionsnummer. bump_version.py ersetzt genau diese Zeile.
      version = "0.1.0";

      branding = import ./branding.nix;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkSystem = import ./lib/mk-system.nix { inherit self nixpkgs version; };

      iso = self.nixosConfigurations."${branding.id}-iso";
    in
    {
      lib = { inherit version mkSystem; };

      # Alle Distro-Module zusammen. Gedacht für lib.mkSystem.
      nixosModules.default = {
        imports = [
          disko.nixosModules.disko
          ./modules
        ];
      };

      # Distro-Module. Jedes Modul liest den Namen selbst aus branding.nix.
      nixosModules.storage = {
        imports = [
          disko.nixosModules.disko
          ./modules/storage/btrfs.nix
        ];
      };

      nixosConfigurations = {
        # Installationsmedium
        "${branding.id}-iso" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit version; };
          modules = [
            ./iso
            { nixpkgs.hostPlatform = system; }
          ];
        };
      };

      packages.${system} = {
        # nix build .#iso
        iso = iso.config.system.build.isoImage;

        # Schnellere Kompression für Testbuilds, das ISO wird etwas grösser
        iso-dev =
          (iso.extendModules {
            modules = [ { isoImage.squashfsCompression = "zstd -Xcompression-level 3"; } ];
          }).config.system.build.isoImage;

        installer = pkgs.callPackage ./installer/package.nix { inherit version; };

        default = self.packages.${system}.iso;
      };

      checks.${system} = import ./tests/eval.nix { inherit self pkgs; };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git-cliff ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
