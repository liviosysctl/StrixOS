# All distro modules. They need the specialArgs from lib/mk-system.nix
# (distroFlake, version), so only use them through mkSystem.
# disko is added in flake.nix because it is a flake input.
{
  imports = [
    ./os-release.nix
    ./base.nix
    ./systemd-tools.nix
    ./boot-splash.nix
    ./theme.nix
    ./tools.nix
    ./apps.nix
    ./storage/btrfs.nix
    ./vmware-guest.nix
  ];
}
