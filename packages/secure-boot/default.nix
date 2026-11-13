# strix-secure-boot: the boot chain shim -> systemd-boot -> kernel on an
# installed machine, signed with a key made on the machine (secure-boot.sh).
{
  lib,
  writeShellApplication,
  coreutils,
  efibootmgr,
  findutils,
  gnugrep,
  gnused,
  mokutil,
  openssl,
  sbsigntool,
  util-linux,
  diffutils,
  shim,
  # systemd-boot as the machine builds it
  systemd,
  esp ? "/boot",
  # Tests only: a folder with key.pem and cert.pem to use instead of a new key
  testKeyDir ? null,
}:

let
  branding = import ../../branding.nix;
in
writeShellApplication {
  name = "${branding.id}-secure-boot";

  runtimeInputs = [
    coreutils
    diffutils
    efibootmgr
    findutils
    gnugrep
    gnused
    mokutil
    openssl
    sbsigntool
    util-linux
  ];

  runtimeEnv = {
    DISTRO_ID = branding.id;
    DISTRO_NAME = branding.name;
    ESP = esp;
    KEY_DIR = "/var/lib/${branding.id}/secure-boot";
    SHIM_DIR = "${shim}/share/shim";
    SYSTEMD_BOOT = "${systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
  }
  // lib.optionalAttrs (testKeyDir != null) {
    TEST_KEY_DIR = testKeyDir;
  };

  text = builtins.readFile ./secure-boot.sh;
}
