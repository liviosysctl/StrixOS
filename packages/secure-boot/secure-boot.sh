# Secure Boot on an installed machine (modules/secure-boot.nix).
#
# The machine boots shim (signed by Microsoft) -> GRUB -> kernel. shim starts
# GRUB and GRUB starts the kernel (through shim) only when they are signed by
# a key shim trusts. That key is made on this machine and never
# leaves it; MokManager adds it to shim's list (the MOK list) once, at the
# keyboard, after "enroll".
#
#   sign         after every boot loader install (extraInstallCommands):
#                make the key if there is none, put shim in front of GRUB,
#                build GRUB as one image and sign it, sign every kernel
#   enroll       ask MokManager to enroll the key at the next start
#                (--code NNNN: the one-time code to type there, default random)
#   boot-entry   a firmware boot entry for shim, first in the boot order
#   status       Secure Boot state, key enrolled or not, what is signed
#
# Layout of the ESP:
#   EFI/BOOT/BOOTX64.EFI   shim (firmware fallback path, and the boot entry)
#   EFI/BOOT/grubx64.efi   GRUB with its modules built in, signed (shim starts
#                          this name); it reads grub/grub.cfg from this ESP
#   EFI/BOOT/mmx64.efi     MokManager
#   kernels/*-bzImage      kernels signed, initrds as they are
#   <id>.cer               the certificate, for "Enroll key from disk"

die() {
  printf '%s-secure-boot: %s\n' "$DISTRO_ID" "$*" >&2
  exit 1
}

say() {
  printf '%s\n' "$*"
}

key="$KEY_DIR/key.pem"
cert="$KEY_DIR/cert.pem"
der="$KEY_DIR/cert.der"
efivars=/sys/firmware/efi/efivars

secure_boot_on() {
  local var="$efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  [ -r "$var" ] && [ "$(od -An -t u1 -j 4 -N 1 "$var" | tr -d ' ')" = 1 ]
}

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run this with sudo"
}

ensure_key() {
  [ -s "$key" ] && [ -s "$cert" ] && [ -s "$der" ] && return 0
  install -d -m 0700 "$KEY_DIR"
  if [ -n "${TEST_KEY_DIR:-}" ]; then
    # Tests only: a fixed key from the store
    install -m 0600 "$TEST_KEY_DIR/key.pem" "$key"
    install -m 0644 "$TEST_KEY_DIR/cert.pem" "$cert"
  else
    local host
    host=$(cat /etc/hostname 2>/dev/null || true)
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
      -subj "/CN=$DISTRO_NAME Secure Boot${host:+ ($host)}" \
      -addext "basicConstraints=critical,CA:FALSE" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" \
      -keyout "$key.new" -out "$cert.new" 2>/dev/null
    chmod 0600 "$key.new"
    mv "$key.new" "$key"
    mv "$cert.new" "$cert"
    say "Made a Secure Boot key for this machine in $KEY_DIR."
  fi
  openssl x509 -in "$cert" -outform DER -out "$der"
}

signed_by_us() {
  sbverify --cert "$cert" "$1" >/dev/null 2>&1
}

sign_to() {
  local from=$1 to=$2
  sbsign --key "$key" --cert "$cert" --output "$to.new" "$from" >/dev/null
  mv "$to.new" "$to"
}

# Copies only when different, so an unchanged ESP is not written again
put() {
  cmp -s "$1" "$2" || install -m 0644 "$1" "$2"
}

# Everything grub.cfg uses, built in: under Secure Boot GRUB loads no module
# from disk. NixOS's grub.cfg, os-prober's entries (Windows is chainloaded,
# the firmware checks its signature), the theme and the firmware settings.
grub_modules=(
  normal configfile echo test true sleep reboot halt minicmd ls cat probe regexp
  search search_fs_uuid search_fs_file search_label part_gpt part_msdos fat ext2 btrfs
  linux chain efifwsetup loadenv keystatus
  all_video efi_gop efi_uga video_bochs video_cirrus gfxterm gfxterm_background gfxmenu png font
)

# GRUB as one image that finds this ESP by its UUID and reads grub/grub.cfg
# there. Signed again only when the unsigned image changed.
sign_grub() {
  local uuid work
  uuid=$(findmnt -nvo UUID --target "$ESP") || die "$ESP is not mounted"
  [ -n "$uuid" ] || die "the file system of $ESP has no UUID"
  work=$(mktemp -d)
  # $root and $prefix are GRUB's, not the shell's
  # shellcheck disable=SC2016
  printf '%s\n' \
    "search --no-floppy --fs-uuid --set=root $uuid" \
    'set prefix=($root)/grub' \
    'configfile $prefix/grub.cfg' >"$work/early.cfg"
  "$GRUB_MKIMAGE" --directory "$GRUB_MODULES" --format x86_64-efi --prefix /grub \
    --config "$work/early.cfg" --output "$work/grubx64.efi" "${grub_modules[@]}"
  if ! cmp -s "$work/grubx64.efi" "$KEY_DIR/grubx64.unsigned" || ! signed_by_us "$ESP/EFI/BOOT/grubx64.efi"; then
    sign_to "$work/grubx64.efi" "$ESP/EFI/BOOT/grubx64.efi"
    install -m 0600 "$work/grubx64.efi" "$KEY_DIR/grubx64.unsigned"
  fi
  rm -rf "$work"
}

cmd_sign() {
  need_root
  [ -d "$ESP/EFI" ] || die "no ESP at $ESP"
  ensure_key

  install -d "$ESP/EFI/BOOT"
  put "$SHIM_DIR/shimx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"
  put "$SHIM_DIR/mmx64.efi" "$ESP/EFI/BOOT/mmx64.efi"
  sign_grub
  put "$der" "$ESP/$DISTRO_ID.cer"

  # Kernels are PE files (MZ), initrds are not. GRUB keeps them in kernels/,
  # installs from before GRUB had them in EFI/nixos/.
  local file count=0
  for file in "$ESP"/kernels/* "$ESP"/EFI/nixos/*.efi; do
    [ -f "$file" ] || continue
    [ "$(head -c 2 "$file")" = MZ ] || continue
    if ! signed_by_us "$file"; then
      sign_to "$file" "$file"
      count=$((count + 1))
    fi
  done
  say "Secure Boot: shim and GRUB in place, $count new kernel(s) signed."
}

esp_disk_and_part() {
  local source dev
  source=$(findmnt -nvo SOURCE --target "$ESP") || die "$ESP is not mounted"
  dev=$(basename "$(readlink -f "$source")")
  [ -r "/sys/class/block/$dev/partition" ] || die "$source is not a partition"
  printf '/dev/%s %s\n' "$(lsblk -no PKNAME "/dev/$dev" | head -n 1)" "$(cat "/sys/class/block/$dev/partition")"
}

cmd_boot_entry() {
  need_root
  [ -d "$efivars" ] || die "no EFI variables (not booted with UEFI?)"
  local disk part number
  read -r disk part <<<"$(esp_disk_and_part)"
  # Remove older entries of the distro, then add one; efibootmgr puts a new
  # entry first in the boot order
  for number in $(efibootmgr | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} $DISTRO_NAME\$/\1/p; s/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} $DISTRO_NAME\t.*/\1/p"); do
    efibootmgr --quiet --bootnum "$number" --delete-bootnum
  done
  efibootmgr --quiet --create --disk "$disk" --part "$part" \
    --label "$DISTRO_NAME" --loader '\EFI\BOOT\BOOTX64.EFI'
  say "Boot entry \"$DISTRO_NAME\" points at shim on $disk, partition $part."
}

cmd_enroll() {
  need_root
  local code=""
  while [ $# -gt 0 ]; do
    case $1 in
      --code)
        code=${2:-}
        shift 2
        ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -z "$code" ] && code=$(shuf -i 1000-9999 -n 1)
  [[ $code =~ ^[0-9]{4,16}$ ]] || die "the code must be 4 to 16 digits (MokManager has a US keyboard)"
  [ -d "$efivars" ] || die "no EFI variables (not booted with UEFI?)"
  ensure_key

  if mokutil --test-key "$der" 2>/dev/null | grep -q 'already enrolled'; then
    say "The key of this machine is already enrolled."
    return 0
  fi

  local hash
  hash=$(mktemp)
  mokutil --generate-hash="$code" >"$hash"
  mokutil --import "$der" --hash-file "$hash"
  rm -f "$hash"
  # MokManager waits for a key instead of the usual 10 seconds
  mokutil --timeout -1 >/dev/null 2>&1 || true

  say "At the next start MokManager asks to enroll the key:"
  say "  any key, Enroll MOK, Continue, Yes, code $code, Reboot"
}

cmd_status() {
  need_root
  if secure_boot_on; then say "Secure Boot: on"; else say "Secure Boot: off"; fi
  if [ -s "$der" ]; then
    if mokutil --test-key "$der" 2>/dev/null | grep -q 'already enrolled'; then
      say "Machine key: enrolled"
    elif mokutil --list-new 2>/dev/null | grep -q .; then
      say "Machine key: waiting for MokManager at the next start"
    else
      say "Machine key: not enrolled (sudo $DISTRO_ID-secure-boot enroll)"
    fi
  else
    say "Machine key: none yet"
  fi
  local file
  for file in "$ESP/EFI/BOOT/grubx64.efi" "$ESP"/kernels/*-bzImage; do
    [ -f "$file" ] || continue
    if signed_by_us "$file"; then say "signed:   ${file#"$ESP"/}"; else say "unsigned: ${file#"$ESP"/}"; fi
  done
}

case ${1:-} in
  sign) cmd_sign ;;
  enroll)
    shift
    cmd_enroll "$@"
    ;;
  boot-entry) cmd_boot_entry ;;
  status) cmd_status ;;
  *) die "usage: $DISTRO_ID-secure-boot sign|enroll [--code NNNN]|boot-entry|status" ;;
esac
