# Alle Distro-Module. Braucht die specialArgs aus lib/mk-system.nix
# (distroFlake, version), darum nur über mkSystem verwenden.
# disko wird in flake.nix dazugenommen, weil es ein Flake-Input ist.
{
  imports = [
    ./os-release.nix
    ./base.nix
    ./boot-splash.nix
    ./tools.nix
    ./apps.nix
    ./storage/btrfs.nix
  ];
}
