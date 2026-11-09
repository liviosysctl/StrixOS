# Made-up machine. CI builds it, and later its system goes into the ISO's
# store, so a real installation has almost nothing left to download.
# Encryption and hibernation are on so cryptsetup and friends are already included.
{ lib, ... }:

let
  branding = import ../../branding.nix;
in
{
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "xhci_pci"
    "usb_storage"
    "sd_mod"
    "virtio_pci"
    "virtio_blk"
  ];

  networking.hostName = "reference";

  ${branding.id} = {
    user = {
      name = branding.id;
      description = "Reference";
    };
    storage = {
      enable = true;
      device = "/dev/vda";
      encrypt = true;
      swapSize = "4G";
      hibernation = true;
    };
  };

  system.stateVersion = lib.trivial.release;

  # Only for the quick test VM (nix run .#nixosConfigurations.<name>.config.system.build.vm).
  # A real installation sets the password with chpasswd, there is no installer here.
  virtualisation.vmVariant = {
    users.users.${branding.id}.initialPassword = branding.id;
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
  };
}
