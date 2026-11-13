# GRUB for the boot chain under Secure Boot: shim (packages/shim) starts it
# from the ISO, then it starts the kernel through shim's loader protocol, so
# both need a signature from the distro key (iso/sign.sh).
#
# Two things shim and GRUB ask for on top of the signature:
#
# - An .sbat section. shim refuses an image without one, and one whose
#   generation is below the machine's SbatLevel. The grub line names the
#   upstream generation this build really has: 2.14 carries the fixes up to
#   the November 2025 CVEs (grub,6), the patch below the one for
#   CVE-2026-97876 (grub,7, the newest entry in shim's SbatLevel_Variable.txt
#   in November 2026). When shim lists a newer generation, add its fixes here
#   and raise the number; claiming it without them is exactly what SBAT exists
#   to prevent.
# - Every module grub.cfg needs built into the image: GRUB refuses to load a
#   module from disk under Secure Boot. iso-image.nix in nixpkgs already does
#   that for the ISO.
#
# nixpkgs' iso-image.nix calls grub-mkimage without --sbat and has no option
# for it, so grub-mkimage gets a wrapper that adds it. The ISO uses this GRUB
# through an overlay (iso/default.nix).
{
  lib,
  grub2_efi,
  makeWrapper,
  writeText,
  homepage,
}:

let
  branding = import ../../branding.nix;
  inherit (grub2_efi) version;

  sbat = writeText "grub-sbat.csv" ''
    sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
    grub,7,Free Software Foundation,grub,${version},https://www.gnu.org/software/grub/
    grub.${branding.id},1,${branding.name},grub,${version},${homepage}
  '';
in
assert lib.assertMsg (version == "2.14")
  "packages/grub-sb: GRUB is now ${version}. Check which CVE fixes it carries, drop the patches it already has and set the grub generation in the SBAT section.";
grub2_efi.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # CVE-2026-97876: the serial command could write to memory and switch off
    # module verification while GRUB still reports lockdown (grub,7).
    # Upstream commit 26beaa3b, backported to 2.14 (without the pl011 driver,
    # which 2.14 does not have).
    ./CVE-2026-97876.patch
  ];

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  postInstall = (old.postInstall or "") + ''
    wrapProgram $out/bin/grub-mkimage --add-flags "--sbat=${sbat}"
  '';

  passthru = (old.passthru or { }) // {
    inherit sbat;
  };
})
