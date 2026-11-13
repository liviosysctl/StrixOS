# Secure Boot on installed machines (main only, the school proof of concept).
#
# The machine boots shim (signed by Microsoft) -> systemd-boot -> kernel, the
# same way the signed ISO boots shim -> GRUB -> kernel. systemd-boot and the
# kernels are signed with a key made on the machine at install time
# (/var/lib/<id>/secure-boot, root only). shim trusts it once MokManager has
# enrolled it: the installer asks for that when Secure Boot is on, later
# `sudo <id>-secure-boot enroll` does the same.
#
# With Secure Boot off everything boots as before, shim then starts
# systemd-boot without checking it.
#
# The initrd is not checked (shim checks only PE images), the same trade-off
# as on the ISO. Lanzaboote would cover it, but needs own keys in the
# firmware's db instead of the MOK list, which a beginner cannot be asked to do.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.secureBoot;
  system = pkgs.stdenv.hostPlatform.system;

  tool = pkgs.callPackage ../packages/secure-boot {
    inherit (distroFlake.packages.${system}) shim;
    systemd = config.systemd.package;
    esp = config.boot.loader.efi.efiSysMountPoint;
    testKeyDir = cfg.testKey;
  };
in
{
  options.${branding.id}.secureBoot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Boot through shim, so the machine also starts with Secure Boot on.
        systemd-boot and every kernel are signed with a key made on this
        machine after each boot loader install. Turning it off leaves the
        files on the ESP until the next install of the boot loader.
      '';
    };

    testKey = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      internal = true;
      description = ''
        Tests only: a folder with key.pem and cert.pem used instead of making
        a key. The key is readable by everyone in the Nix store.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && config.boot.loader.systemd-boot.enable) {
    boot.loader.systemd-boot.extraInstallCommands = ''
      ${lib.getExe tool} sign
    '';

    # A boot entry made by bootctl would point the firmware at systemd-boot
    # directly, which the firmware refuses with Secure Boot on (it only knows
    # Microsoft's keys). The installer makes one for shim instead
    # (`<id>-secure-boot boot-entry`), and the fallback path
    # EFI/BOOT/BOOTX64.EFI is shim as well.
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

    environment.systemPackages = [
      tool
      pkgs.mokutil
    ];
  };
}
