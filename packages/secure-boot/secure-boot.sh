# Secure Boot on an installed machine (modules/secure-boot.nix).
#
# The machine boots shim (signed by Microsoft) -> GRUB -> kernel. shim starts
# GRUB and GRUB starts the kernel (through shim) only when they are signed by
# a key shim trusts. Normally that is the distro key, the one the stick is
# signed with: shim already trusts it after the one enrollment from the stick.
# CI signs GRUB and the kernel with it once (secure-boot/README.md); here the
# signatures are only attached. A kernel CI has not signed (another kernel in
# machine.nix) is signed with a key made on this machine instead, which then
# needs an enrollment of its own.
#
#   sign          after every boot loader install (extraInstallCommands): put
#                 shim in front of GRUB, put the signed GRUB and sign every
#                 kernel
#   needs-enroll  exit 0 if shim does not trust every key the boot files are
#                 signed with yet (the installer shows a code only then)
#   enroll        ask MokManager to enroll those keys at the next start
#                 (--code NNNN: the one-time code to type there, default random)
#   boot-entry    a firmware boot entry for shim, first in the boot order
#   status        Secure Boot state, keys enrolled or not, what is signed
#
# Layout of the ESP:
#   EFI/BOOT/BOOTX64.EFI   shim (firmware fallback path, and the boot entry)
#   EFI/BOOT/grubx64.efi   GRUB with its modules built in, signed (shim starts
#                          this name); it reads grub/grub.cfg from this ESP
#   EFI/BOOT/mmx64.efi     MokManager
#   kernels/*-bzImage      kernels signed, initrds as they are
#   <id>.cer               the distro certificate, for "Enroll key from disk"
#   <id>-machine.cer       the machine's certificate, once a kernel needed it

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
distro_der="$KEY_DIR/distro.der"
efivars=/sys/firmware/efi/efivars

secure_boot_on() {
  local var="$efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  [ -r "$var" ] && [ "$(od -An -t u1 -j 4 -N 1 "$var" | tr -d ' ')" = 1 ]
}

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run this with sudo"
}

# The distro certificate in DER, as MokManager and mokutil read it
distro_cert() {
  install -d -m 0700 "$KEY_DIR"
  openssl x509 -in "$DISTRO_CERT" -outform DER -out "$distro_der"
}

have_machine_key() {
  [ -s "$key" ] && [ -s "$cert" ] && [ -s "$der" ]
}

ensure_machine_key() {
  have_machine_key && return 0
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

signed_by_distro() {
  sbverify --cert "$DISTRO_CERT" "$1" >/dev/null 2>&1
}

signed_by_machine() {
  have_machine_key && sbverify --cert "$cert" "$1" >/dev/null 2>&1
}

# The distro signature CI made for exactly this unsigned file, if there is one
distro_signature() {
  local sha
  sha=$(sha256sum <"$1" | cut -d ' ' -f 1)
  [ -e "$SIGNATURES/$sha.p7" ] && printf '%s\n' "$SIGNATURES/$sha.p7"
}

# Copies only when different, so an unchanged ESP is not written again
put() {
  cmp -s "$1" "$2" || install -m 0644 "$1" "$2"
}

# Writes <to> as the unsigned <from> with a signature: the distro's if CI made
# one, else one with the machine key. Prints "distro" or "machine".
sign_to() {
  local from=$1 to=$2 sig work
  work=$(mktemp)
  install -m 0644 "$from" "$work"
  if sig=$(distro_signature "$from"); then
    sbattach --attach "$sig" "$work" >/dev/null
    signed_by_distro "$work" || die "the signature for ${from##*/} does not fit"
    mv "$work" "$to"
    echo distro
  else
    ensure_machine_key >&2
    sbsign --key "$key" --cert "$cert" --output "$work.signed" "$work" >/dev/null
    rm -f "$work"
    mv "$work.signed" "$to"
    echo machine
  fi
}

cmd_sign() {
  need_root
  [ -d "$ESP/EFI" ] || die "no ESP at $ESP"
  distro_cert

  install -d "$ESP/EFI/BOOT"
  put "$SHIM_DIR/shimx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"
  put "$SHIM_DIR/mmx64.efi" "$ESP/EFI/BOOT/mmx64.efi"
  put "$distro_der" "$ESP/$DISTRO_ID.cer"

  # GRUB is the same image on every machine. Written again when the image
  # changed, when it is unsigned, or when a distro signature replaces the
  # machine's.
  local grub="$ESP/EFI/BOOT/grubx64.efi" last="$KEY_DIR/grubx64.unsigned"
  if ! cmp -s "$GRUB_IMAGE" "$last" ||
    ! { signed_by_distro "$grub" || { signed_by_machine "$grub" && ! distro_signature "$GRUB_IMAGE" >/dev/null; }; }; then
    sign_to "$GRUB_IMAGE" "$grub" >/dev/null
    install -m 0600 "$GRUB_IMAGE" "$last"
  fi

  # Kernels are PE files (MZ), initrds are not. GRUB keeps them in kernels/,
  # installs from before GRUB had them in EFI/nixos/.
  local file by distro=0 machine=0
  for file in "$ESP"/kernels/* "$ESP"/EFI/nixos/*.efi; do
    [ -f "$file" ] || continue
    [ "$(head -c 2 "$file")" = MZ ] || continue
    signed_by_distro "$file" && continue
    signed_by_machine "$file" && continue
    by=$(sign_to "$file" "$file")
    if [ "$by" = distro ]; then distro=$((distro + 1)); else machine=$((machine + 1)); fi
  done
  if have_machine_key; then
    put "$der" "$ESP/$DISTRO_ID-machine.cer"
  fi
  say "Secure Boot: shim and GRUB in place; new kernels: $distro with the $DISTRO_NAME key, $machine with the machine key."
  if [ "$machine" -gt 0 ] && secure_boot_on && ! enrolled "$der"; then
    say "A kernel has no $DISTRO_NAME signature and shim does not trust the machine key yet: run sudo $DISTRO_ID-secure-boot enroll before the next start."
  fi
}

# The keys the boot files on the ESP are signed with, as DER files
keys_in_use() {
  local file distro=false machine=false
  for file in "$ESP/EFI/BOOT/grubx64.efi" "$ESP"/kernels/* "$ESP"/EFI/nixos/*.efi; do
    [ -f "$file" ] || continue
    [ "$(head -c 2 "$file")" = MZ ] || continue
    if signed_by_distro "$file"; then
      distro=true
    elif signed_by_machine "$file"; then
      machine=true
    fi
  done
  if $distro; then
    distro_cert
    printf '%s\n' "$distro_der"
  fi
  if $machine; then
    printf '%s\n' "$der"
  fi
}

enrolled() {
  mokutil --test-key "$1" 2>/dev/null | grep -q 'already enrolled'
}

# The keys in use that shim does not trust yet
keys_missing() {
  local der_file
  while read -r der_file; do
    enrolled "$der_file" || printf '%s\n' "$der_file"
  done < <(keys_in_use)
}

cmd_needs_enroll() {
  need_root
  [ -d "$efivars" ] || exit 1
  [ -n "$(keys_missing)" ]
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

  local missing=()
  mapfile -t missing < <(keys_missing)
  if [ ${#missing[@]} -eq 0 ]; then
    say "shim already trusts every key the boot files are signed with."
    return 0
  fi

  local hash
  hash=$(mktemp)
  mokutil --generate-hash="$code" >"$hash"
  mokutil --import "${missing[@]}" --hash-file "$hash"
  rm -f "$hash"
  # MokManager waits for a key instead of the usual 10 seconds
  mokutil --timeout -1 >/dev/null 2>&1 || true

  say "At the next start MokManager asks to enroll the key:"
  say "  any key, Enroll MOK, Continue, Yes, code $code, Reboot"
}

cmd_status() {
  need_root
  if secure_boot_on; then say "Secure Boot: on"; else say "Secure Boot: off"; fi
  distro_cert
  if enrolled "$distro_der"; then
    say "$DISTRO_NAME key: enrolled"
  else
    say "$DISTRO_NAME key: not enrolled (sudo $DISTRO_ID-secure-boot enroll)"
  fi
  if have_machine_key; then
    if enrolled "$der"; then
      say "Machine key: enrolled"
    else
      say "Machine key: not enrolled (sudo $DISTRO_ID-secure-boot enroll)"
    fi
  fi
  if mokutil --list-new 2>/dev/null | grep -q .; then
    say "MokManager asks to enroll a key at the next start."
  fi
  local file
  for file in "$ESP/EFI/BOOT/grubx64.efi" "$ESP"/kernels/*-bzImage; do
    [ -f "$file" ] || continue
    if signed_by_distro "$file"; then
      say "$DISTRO_NAME key: ${file#"$ESP"/}"
    elif signed_by_machine "$file"; then
      say "machine key: ${file#"$ESP"/}"
    else
      say "unsigned: ${file#"$ESP"/}"
    fi
  done
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

case ${1:-} in
  sign) cmd_sign ;;
  needs-enroll) cmd_needs_enroll ;;
  enroll)
    shift
    cmd_enroll "$@"
    ;;
  boot-entry) cmd_boot_entry ;;
  status) cmd_status ;;
  *) die "usage: $DISTRO_ID-secure-boot sign|needs-enroll|enroll [--code NNNN]|boot-entry|status" ;;
esac
