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
      # The only place with the version number. bump_version.py replaces exactly this line.
      version = "0.1.0";

      # Where installed machines get updates from. The branch differs between
      # main (school proof of concept) and personal.
      upstream = {
        owner = "liviosysctl";
        repo = "strixos";
        ref = "main";
      };

      branding = import ./branding.nix;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkSystem = import ./lib/mk-system.nix { inherit self nixpkgs version; };

      iso = self.nixosConfigurations."${branding.id}-iso";
    in
    {
      lib = { inherit version mkSystem; };

      # All distro modules together. Meant to be used through lib.mkSystem.
      nixosModules.default = {
        imports = [
          disko.nixosModules.disko
          ./modules
        ];
      };

      # Distro modules. Every module reads the name from branding.nix itself.
      nixosModules.storage = {
        imports = [
          disko.nixosModules.disko
          ./modules/storage/btrfs.nix
        ];
      };

      nixosConfigurations = {
        # Installer medium
        "${branding.id}-iso" = nixpkgs.lib.nixosSystem {
          specialArgs = {
            distroFlake = self;
            inherit version;
          };
          modules = [
            ./iso
            { nixpkgs.hostPlatform = system; }
          ];
        };

        # Made-up machine for CI and the ISO's store
        "${branding.id}-reference" = mkSystem {
          modules = [ ./hosts/reference ];
          apps = ./templates/machine/apps.json;
        };

        # Test machine for VMware Workstation, with guest tools
        "${branding.id}-vmware" = mkSystem {
          modules = [ ./hosts/vmware ];
          apps = ./templates/machine/apps.json;
        };
      };

      packages.${system} = {
        # nix build .#iso
        iso = iso.config.system.build.isoImage;

        # Faster compression for test builds, the ISO gets slightly larger
        iso-dev =
          (iso.extendModules {
            modules = [ { isoImage.squashfsCompression = "zstd -Xcompression-level 3"; } ];
          }).config.system.build.isoImage;

        installer = pkgs.callPackage ./installer/package.nix { inherit version; };

        # Template for /etc/nixos with the distro name filled in, for the installer
        machine-template = pkgs.runCommand "${branding.id}-machine-template" { } ''
          cp -r ${./templates/machine} $out
          chmod -R u+w $out
          substituteInPlace $out/flake.nix $out/machine.nix --replace-fail @distroId@ ${branding.id}
          substituteInPlace $out/flake.nix \
            --replace-fail @distroUrl@ github:${upstream.owner}/${upstream.repo}/${upstream.ref}
        '';

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
