# Testmaschine für VMware Workstation. Die einzige Konfiguration mit Gast-Tools.
{ lib, ... }:

let
  branding = import ../../branding.nix;
in
{
  imports = [ ../reference ];

  networking.hostName = lib.mkForce "vmware";

  # Fenstergrösse passt sich an, Zwischenablage geht
  virtualisation.vmware.guest.enable = true;

  ${branding.id}.storage.device = lib.mkForce "/dev/nvme0n1";
}
