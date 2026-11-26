# What the machine itself needs looked after.
{
  imports = [
    ./firmware.nix
    ./kernel.nix
    ./memory.nix
    ./thermal.nix
  ];
}
