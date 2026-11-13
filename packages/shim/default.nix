# shim and MokManager from Debian, already signed: shim by Microsoft
# ("Microsoft Corporation UEFI CA 2011", the third-party CA that PCs with
# Secure Boot trust), MokManager by Debian's key, which that shim carries.
# Getting an own shim signed would mean Microsoft's shim review; Ventoy and
# other small distributions reuse a signed one the same way.
#
# shim then starts grubx64.efi (the ISO) or systemd-boot (installed machines)
# from its own folder if the binary is signed by a key in the machine's MOK
# list, and MokManager when it is not. The version also sets the lowest SBAT
# generation shim accepts: 16.1-2 wants grub,5 (see packages/grub-sb).
#
# The 2011 CA expired in June 2026. Firmware does not check the expiry, so
# binaries signed before that keep booting; this build was signed in May 2026.
{ lib, stdenvNoCC, fetchurl, binutils, xz }:

let
  debian = "https://deb.debian.org/debian/pool/main/s";
in
stdenvNoCC.mkDerivation {
  pname = "shim-signed";
  version = "16.1-2";

  srcs = [
    (fetchurl {
      name = "shim-signed.deb";
      url = "${debian}/shim-signed/shim-signed_1.51~1+deb12u1+16.1-2~deb12u1_amd64.deb";
      hash = "sha256-wqz15VlmS7rbfOV4n5oyHzl1SjSFTTCXuMwDad9ROzs=";
    })
    (fetchurl {
      name = "shim-helpers-signed.deb";
      url = "${debian}/shim-helpers-amd64-signed/shim-helpers-amd64-signed_1+16.1+2~deb12u1_amd64.deb";
      hash = "sha256-JqysNRM5RsFkKgnz/aNT7juEnl/GQ/rbl6jf7J4rVfs=";
    })
  ];

  nativeBuildInputs = [ binutils xz ];

  unpackCmd = ''
    mkdir "$(stripHash "$curSrc" | sed 's/\.deb$//')"
    (cd "$(stripHash "$curSrc" | sed 's/\.deb$//')" && ar x "$curSrc" && tar xf data.tar.xz)
  '';
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm444 shim-signed/usr/lib/shim/shimx64.efi.signed $out/share/shim/shimx64.efi
    install -Dm444 shim-helpers-signed/usr/lib/shim/mmx64.efi.signed $out/share/shim/mmx64.efi
    runHook postInstall
  '';

  meta = {
    description = "Microsoft-signed shim and MokManager from Debian";
    homepage = "https://github.com/rhboot/shim";
    license = lib.licenses.bsd2;
    platforms = [ "x86_64-linux" ];
  };
}
