# The core of the installer. Reads an answers file and installs without
# asking anything. The text front end, a later graphical one and the
# automated test all call this.
#
# Secrets never go into the answers file:
#   $password_file   the user's password, one line
#   $luks_key_file   the disk passphrase without a newline (only with encryption)

install_steps=(
  "Checking the answers and this computer"
  "Writing the configuration"
  "Checking the configuration before touching the disk"
  "Partitioning, encrypting and formatting the disk"
  "Copying the configuration onto the disk"
  "Installing the system"
  "Setting the password"
  "Keeping the log"
  "Finishing"
)
total_steps=${#install_steps[@]}

# The log keeps these English titles, the console installer shows st1 to st9
# from i18n.sh in the chosen language.

# Shown next to the spinner while a step runs, keys in i18n.sh
step_hints=(
  hint_seconds
  hint_seconds
  hint_minute
  hint_minute
  hint_seconds
  hint_minutes
  hint_seconds
  hint_seconds
  hint_seconds
)
current_step=0
mounted=0

step() {
  current_step=$1
  printf '\n[%s/%s] %s\n' "$1" "$total_steps" "${install_steps[$1 - 1]}" >>"$log_file"
  if [ "$ui_fancy" -eq 1 ]; then
    draw_install "$1"
  else
    printf '\n[%s/%s] %s\n' "$1" "$total_steps" "${install_steps[$1 - 1]}" >&2
  fi
}

# Runs a command: in the console installer behind a spinner with the output
# only in the log, otherwise with the output shown and logged
run() {
  if [ "$ui_fancy" -eq 1 ]; then
    spin "$(tf "${step_hints[$current_step - 1]}" "$log_file")" "$@"
  else
    "$@" 2>&1 | tee -a "$log_file"
  fi
}

shred_secrets() {
  local file
  for file in "$password_file" "$luks_key_file"; do
    if [ -e "$file" ]; then
      shred -u "$file" 2>/dev/null || rm -f "$file"
    fi
  done
}

release_disk() {
  swapoff -a 2>/dev/null || true
  umount -R /mnt 2>/dev/null || true
  cryptsetup close "$luks_name" 2>/dev/null || true
}

on_core_exit() {
  local status=$?
  shred_secrets
  if [ "$status" -ne 0 ]; then
    if [ "$mounted" -eq 1 ]; then
      release_disk
    fi
    if [ "$ui_fancy" -eq 1 ]; then
      draw_failure
    else
      printf '\nInstallation failed. The full log is in %s\n' "$log_file" >&2
    fi
  fi
}

# One value from the answers file as text. Not jq -e: that fails on the
# value false, which is a normal answer here (encryption or hibernation off).
answer() {
  local value
  value=$(jq -r "$1 | if . == null then \"\" else tostring end" "$answers_file")
  [ -n "$value" ] || die "The answers file has no value for $1"
  printf '%s' "$value"
}

# Fills the placeholders of the machine.nix template
render_machine_nix() {
  local template=$1 content console_map xkb_layout xkb_variant leftover
  read -r console_map xkb_layout xkb_variant <<<"$(keyboard_settings "$keyboard")" || true

  content=$(<"$template")
  content=${content//@hostName@/$host_name}
  content=${content//@timeZone@/$time_zone}
  content=${content//@locale@/$locale}
  content=${content//@consoleKeyMap@/$console_map}
  content=${content//@xkbLayout@/$xkb_layout}
  content=${content//@xkbVariant@/$xkb_variant}
  content=${content//@userName@/$user_name}
  content=${content//@disk@/$disk}
  content=${content//@encrypt@/$encrypt}
  content=${content//@swapSize@/$swap}
  content=${content//@hibernation@/$hibernation}
  content=${content//@stateVersion@/$STATE_VERSION}

  # Check before the free text goes in, so a name with @ signs cannot look
  # like a placeholder
  leftover=$(grep -oE '@[A-Za-z]+@' <<<"$content" | grep -vx '@fullName@' | head -n 1 || true)
  [ -z "$leftover" ] || die "machine.nix still has an unfilled placeholder: $leftover"

  content=${content//@fullName@/$(nix_escape "$full_name")}
  printf '%s\n' "$content"
}

read_answers() {
  host_name=$(answer .hostName)
  time_zone=$(answer .timeZone)
  locale=$(answer .locale)
  keyboard=$(answer .keyboard)
  user_name=$(answer .user.name)
  full_name=$(answer .user.fullName)
  disk=$(answer .disk)
  encrypt=$(answer .encrypt)
  hibernation=$(answer .hibernation)

  # Checked again here: the answers file may come from somewhere other than
  # the text front end, e.g. the automated test.
  valid_host_name "$host_name" || die "Not a valid computer name: $host_name"
  valid_time_zone "$time_zone" || die "Unknown time zone: $time_zone"
  valid_locale "$locale" || die "Unsupported language: $locale"
  keyboard_settings "$keyboard" >/dev/null || die "Unknown keyboard: $keyboard"
  valid_user_name "$user_name" || die "Not a valid user name: $user_name"
  valid_full_name "$full_name" || die "The name must be 1 to 64 characters on one line."
  [ -b "$disk" ] || die "Not a disk: $disk"
  [[ $encrypt == true || $encrypt == false ]] || die "encrypt must be true or false"
  [[ $hibernation == true || $hibernation == false ]] || die "hibernation must be true or false"
}

check_disk() {
  local device name boot disk_gib
  device=$(readlink -f "$disk")
  name=$(basename "$device")
  boot=$(boot_disk)
  [ "$name" != "$boot" ] || die "$disk is the stick the installer runs from."
  [ "$(disk_bytes "$device")" -ge "$min_disk_bytes" ] || die "$disk is smaller than 32 GiB."

  disk_gib=$(($(disk_bytes "$device") / 1073741824))
  if [ "$hibernation" = true ] && ! hibernation_fits "$disk_gib" "$(ram_gib)"; then
    die "The disk is too small for hibernation with $(ram_gib) GiB of RAM."
  fi
}

write_config() {
  local stage=$1 hardware_nix=$2 file
  rm -rf "$stage"
  install -d -m 0755 "$stage"

  # Every file of the template except its README, so this works on branches
  # with and without apps.json
  for file in "$TEMPLATE_DIR"/*; do
    case ${file##*/} in
      README.md | machine.nix) ;;
      *) install -m 0644 "$file" "$stage/" ;;
    esac
  done
  render_machine_nix "$TEMPLATE_DIR/machine.nix" >"$stage/machine.nix"
  chmod 0644 "$stage/machine.nix"

  if [ -n "$hardware_nix" ]; then
    install -m 0644 "$hardware_nix" "$stage/hardware.nix"
  else
    nixos-generate-config --no-filesystems --show-hardware-config >"$stage/hardware.nix"
  fi

  if [ -n "${MACHINE_LOCK:-}" ]; then
    install -m 0644 "$MACHINE_LOCK" "$stage/flake.lock"
  else
    log "This ISO has no prepared lock file, locking now (needs the network)."
    run nix flake lock "$stage"
  fi
}

install_from_answers() {
  local hardware_nix=$1 unmount=$2 stage="$work_dir/etc-nixos"
  trap on_core_exit EXIT
  # Any command that fails without a message of its own still leaves a line
  # in the log saying which one it was
  set -o errtrace
  trap 'printf "Failed (exit %s): %s\n" "$?" "$BASH_COMMAND" >>"$log_file"' ERR

  [ "$ui_fancy" -eq 1 ] || : >"$log_file"
  step 1
  check_root
  check_uefi
  check_ram
  read_answers
  check_disk
  if [ "$encrypt" = true ] && [ ! -s "$luks_key_file" ]; then
    die "Encryption is on, but there is no passphrase in $luks_key_file."
  fi
  [ -s "$password_file" ] || die "There is no password in $password_file."
  swap=$(swap_size "$(ram_gib)" "$hibernation")
  log "Installing on $disk, swap $swap, encryption $encrypt, hibernation $hibernation"

  step 2
  write_config "$stage" "$hardware_nix"

  step 3
  run nix eval --raw "$stage#nixosConfigurations.${DISTRO_ID}.config.system.build.toplevel.drvPath"

  step 4
  mounted=1
  run disko --mode destroy,format,mount --yes-wipe-all-disks --flake "$stage#${DISTRO_ID}"
  shred_secrets_luks_only

  step 5
  install -d -m 0755 /mnt/etc/nixos
  cp -a "$stage/." /mnt/etc/nixos/
  chown -R root:root /mnt/etc/nixos

  step 6
  run nixos-install --root /mnt --flake "/mnt/etc/nixos#${DISTRO_ID}" --no-root-passwd --no-channel-copy

  step 7
  printf '%s:%s\n' "$user_name" "$(<"$password_file")" | nixos-enter --root /mnt -c chpasswd
  shred_secrets

  step 8
  install -D -m 0600 "$log_file" "/mnt/var/log/${DISTRO_ID}-install.log"

  step 9
  setup_secure_boot
  sync
  if [ "$unmount" -eq 1 ]; then
    release_disk
    mounted=0
  fi
  printf '\nDone.\n' >>"$log_file"
}

# Only machines with modules/secure-boot.nix (main) have this tool, so the
# same installer works on every branch. It points a firmware boot entry at
# shim and, with Secure Boot on, asks MokManager to enroll the machine's key
# at the next start; the done screen shows the code to type there.
mok_code=""
mok_from_disk=0
setup_secure_boot() {
  local tool="${DISTRO_ID}-secure-boot" code
  nixos-enter --root /mnt -c "command -v $tool" >/dev/null 2>&1 || return 0
  run nixos-enter --root /mnt -c "$tool boot-entry" ||
    log "No boot entry for shim, the firmware will start the fallback path EFI/BOOT/BOOTX64.EFI."
  secure_boot_enabled || return 0
  code=$(shuf -i 1000-9999 -n 1)
  if run nixos-enter --root /mnt -c "$tool enroll --code $code"; then
    mok_code=$code
  else
    log "Could not ask MokManager to enroll the key, it can still be enrolled from disk."
    mok_from_disk=1
  fi
}

# The passphrase is only needed while formatting
shred_secrets_luks_only() {
  if [ -e "$luks_key_file" ]; then
    shred -u "$luks_key_file" 2>/dev/null || rm -f "$luks_key_file"
  fi
}
