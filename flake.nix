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
      branding = import ./branding.nix;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Distro-Module. Der Name kommt aus branding.nix und wird jedem Modul
      # als Argument mitgegeben.
      nixosModules.storage = {
        imports = [
          disko.nixosModules.disko
          ./modules/storage/btrfs.nix
        ];
        _module.args = { inherit branding; };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git-cliff ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
