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
    { nixpkgs, disko, ... }:
    let
      # Einzige Stelle mit der Versionsnummer. bump_version.py ersetzt genau diese Zeile.
      version = "0.1.0";

      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      lib = { inherit version; };

      # Distro-Module. Jedes Modul liest den Namen selbst aus branding.nix.
      nixosModules.storage = {
        imports = [
          disko.nixosModules.disko
          ./modules/storage/btrfs.nix
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git-cliff ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
