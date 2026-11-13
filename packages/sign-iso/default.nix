# sign-iso IN.iso OUT.iso: signs the installer ISO for Secure Boot with the
# key from SECURE_BOOT_KEY (sign-iso.sh). CI runs it with the key from a
# secret: nix run .#sign-iso -- in.iso out.iso
{
  writeShellApplication,
  binutils,
  coreutils,
  dosfstools,
  findutils,
  gnugrep,
  gnused,
  libfaketime,
  mtools,
  openssl,
  sbsigntool,
  xorriso,
  shim,
}:

let
  branding = import ../../branding.nix;
in
writeShellApplication {
  name = "sign-iso";

  runtimeInputs = [
    binutils
    coreutils
    dosfstools
    findutils
    gnugrep
    gnused
    libfaketime
    mtools
    openssl
    sbsigntool
    xorriso
  ];

  runtimeEnv = {
    DISTRO_ID = branding.id;
    SHIM_DIR = "${shim}/share/shim";
  };

  text = builtins.readFile ./sign-iso.sh;
}
