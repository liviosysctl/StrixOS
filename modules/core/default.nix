# What every machine has, also without a screen.
{
  imports = [
    ./os-release.nix
    ./base.nix
    ./cache.nix
    ./systemd-tools.nix
    ./tools.nix
  ];
}
