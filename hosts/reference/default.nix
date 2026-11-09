# Erfundene Maschine. CI baut sie, und später landet ihr System im Store
# des ISOs, damit eine echte Installation fast nichts herunterladen muss.
# Darum mit Verschlüsselung und Ruhezustand: so sind cryptsetup und Co. schon dabei.
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
}
