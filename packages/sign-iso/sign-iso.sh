# Signs an installer ISO for Secure Boot. Runs outside of Nix (in CI with the
# key from a secret), so the private key never ends up in the Nix store.
#
#   sign-iso IN.iso OUT.iso
#
# Environment:
#   SECURE_BOOT_KEY    the private key (PEM file)
#   SECURE_BOOT_CERT   its certificate (PEM file), the one in secure-boot/
#
# What changes, in the EFI image (/boot/efi.img, the partition firmware boots
# from a stick) and in the ISO's /EFI tree alike:
#
#   EFI/BOOT/BOOTX64.EFI   shim, signed by Microsoft (was GRUB)
#   EFI/BOOT/grubx64.efi   GRUB, signed with the key; shim starts it
#   EFI/BOOT/mmx64.efi     MokManager, for enrolling the key
#   <id>.cer               the certificate, for "Enroll key from disk"
#
# and every kernel under /boot is signed with the key, since GRUB starts it
# through shim. The initrd is not signed: shim checks only PE images.
#
# The boot records (El Torito, the hybrid MBR and GPT for sticks) are written
# again from the input with xorriso's "replay", pointing at the new files.

die() {
  printf 'sign-iso: %s\n' "$*" >&2
  exit 1
}

[ $# -eq 2 ] || die "usage: sign-iso IN.iso OUT.iso"
in=$(realpath "$1")
out=$(realpath -m "$2")
[ -f "$in" ] || die "no such file: $1"
[ "$in" != "$out" ] || die "IN and OUT must differ"
key=${SECURE_BOOT_KEY:?set SECURE_BOOT_KEY to the private key (PEM)}
cert=${SECURE_BOOT_CERT:?set SECURE_BOOT_CERT to the certificate (PEM)}
[ -r "$key" ] || die "cannot read the key $key"
[ -r "$cert" ] || die "cannot read the certificate $cert"

# A key that does not belong to the certificate would give an ISO that no
# enrolled machine accepts. Compare the public keys.
if [ "$(openssl pkey -in "$key" -pubout)" != "$(openssl x509 -in "$cert" -noout -pubkey)" ]; then
  die "the key does not belong to the certificate $cert"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# Paths in the ISO, quoted by xorriso: '/boot/nix/store/...-linux-6.18/bzImage'
iso_find() {
  xorriso -indev "$in" -find "$1" -type f -name "$2" 2>/dev/null | sed -n "s/^'\(.*\)'\$/\1/p"
}

extract() {
  xorriso -osirrox on -indev "$in" -extract "$1" "$2" 2>/dev/null
  chmod u+w "$2"
}

sign() {
  sbsign --key "$key" --cert "$cert" --output "$2" "$1" >/dev/null
  sbverify --cert "$cert" "$2" >/dev/null
}

# 1. The EFI image: take every file out, change them, build a new image
extract /boot/efi.img efi.img
mkdir esp
mcopy -s -n -i efi.img ::/EFI esp/
chmod -R u+w esp
grub=esp/EFI/BOOT/BOOTX64.EFI
[ -f "$grub" ] || die "the EFI image has no EFI/BOOT/BOOTX64.EFI"
if sbverify --list "$grub" 2>&1 | grep -q '^signature'; then
  die "the ISO is signed already (BOOTX64.EFI carries a signature)"
fi
objdump -h "$grub" | grep -q '\.sbat' || die "GRUB has no .sbat section, shim would refuse it (packages/grub-sb)"

sign "$grub" grubx64.efi
openssl x509 -in "$cert" -outform DER -out "$DISTRO_ID.cer"

install -m 0644 grubx64.efi esp/EFI/BOOT/grubx64.efi
install -m 0644 "$SHIM_DIR/shimx64.efi" esp/EFI/BOOT/BOOTX64.EFI
install -m 0644 "$SHIM_DIR/mmx64.efi" esp/EFI/BOOT/mmx64.efi
install -m 0644 "$DISTRO_ID.cer" "esp/$DISTRO_ID.cer"

# Same layout as nixpkgs' iso-image.nix: fixed dates, label and serial, 10 %
# room for the FAT, rounded up to whole MiB
find esp -exec touch --date=2000-01-01 {} +
usage=$(du -s --block-size=1M --apparent-size esp | cut -f1)
size=$(((usage * 1024 * 1024 * 110 / 100 / 1048576 + 2) * 1048576))
truncate --size="$size" efi.new
mkfs.vfat --invariant -i 12345678 -n EFIBOOT efi.new >/dev/null
(
  cd esp
  for d in $(find . -mindepth 1 -type d | sort); do
    faketime "2000-01-01 00:00:00" mmd -i ../efi.new "::/${d#./}"
  done
  for f in $(find . -type f | sort); do
    mcopy -pvm -i ../efi.new "$f" "::/${f#./}" >/dev/null
  done
)
fsck.vfat -n efi.new >/dev/null || die "the new EFI image is broken"

# 2. Every kernel
maps=()
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$((n + 1))
  extract "$path" "kernel-$n"
  sign "kernel-$n" "kernel-$n.signed"
  maps+=(-map "kernel-$n.signed" "$path")
done < <(iso_find /boot bzImage)
[ "$n" -gt 0 ] || die "found no kernel (bzImage) under /boot"

# 3. A new ISO with the changed files
xorriso \
  -indev "$in" \
  -outdev "$out" \
  -boot_image any replay \
  -joliet on \
  -compliance iso_9660_level=3 \
  -map efi.new /boot/efi.img \
  -map esp/EFI/BOOT/BOOTX64.EFI /EFI/BOOT/BOOTX64.EFI \
  -map grubx64.efi /EFI/BOOT/grubx64.efi \
  -map "$SHIM_DIR/mmx64.efi" /EFI/BOOT/mmx64.efi \
  -map "$DISTRO_ID.cer" "/$DISTRO_ID.cer" \
  "${maps[@]}" \
  2>xorriso.log || {
  cat xorriso.log >&2
  die "xorriso failed"
}

printf 'Signed %s: shim, GRUB and %s kernel(s), certificate %s.cer\n' "$out" "$n" "$DISTRO_ID"
