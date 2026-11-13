# All distro modules. They need the specialArgs from lib/mk-system.nix
# (distroFlake, version), so only use them through mkSystem.
# disko is added in flake.nix because it is a flake input.
{
  imports = [
    ./os-release.nix
    ./base.nix
    ./cache.nix
    ./systemd-tools.nix
    ./boot-splash.nix
    ./theme.nix
    ./ui.nix
    ./desktop.nix
    ./neovim.nix
    ./tools.nix
    ./apps.nix
    ./store.nix
    ./secure-boot.nix
    ./search.nix
    ./storage/btrfs.nix
  ];
}
