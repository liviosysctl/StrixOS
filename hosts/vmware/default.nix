# Test machine for VMware Workstation. The only configuration with guest tools.
{ lib, ... }:

let
  branding = import ../../branding.nix;
in
{
  imports = [ ../reference ];

  networking.hostName = lib.mkForce "vmware";

  # Display follows the window size, clipboard works
  virtualisation.vmware.guest.enable = true;

  ${branding.id}.storage.device = lib.mkForce "/dev/nvme0n1";
}
