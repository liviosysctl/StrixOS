# The newest kernel, for hardware that is newer than the long-term kernel knows: a laptop of this
# year, its Wi-Fi, its graphics. The ISO keeps the kernel of the NixOS installer.
{ lib, pkgs, ... }:

{
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
}
