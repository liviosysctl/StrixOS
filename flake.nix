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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
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
