# The core of the installer. Reads an answers file and installs without
# asking anything. The text front end, a later graphical one and the
# automated test all call this.
#
# Secrets never go into the answers file:
#   $password_file   the user's password, one line
#   $luks_key_file   the disk passphrase without a newline (only with encryption)

total_steps=9
mounted=0

step() {
  printf '\n[%s/%s] %s\n' "$1" "$total_steps" "$2" | tee -a "$log_file" >&2
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
    printf '\nInstallation failed. The full log is in %s\n' "$log_file" >&2
  fi
}

answer() {
  jq -er "$1" "$answers_file"
}

# Fills the placeholders of the machine.nix template
render_machine_nix() {
  local template=$1 content console_map xkb_layout xkb_variant vmware_line="" leftover
  read -r console_map xkb_layout xkb_variant <<<"$(keyboard_settings "$keyboard")" || true

  if [ "$virtualization" = vmware ]; then
    vmware_line=$'\n  # Detected VMware: guest tools for display resizing and the clipboard\n  virtualisation.vmware.guest.enable = true;\n'
  fi

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
  content=${content//@vmwareLine@/$vmware_line}
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

  : >"$log_file"
  step 1 "Checking the answers and this computer"
  check_root
  check_uefi
  check_ram
  read_answers
  check_disk
  if [ "$encrypt" = true ] && [ ! -s "$luks_key_file" ]; then
    die "Encryption is on, but there is no passphrase in $luks_key_file."
  fi
  [ -s "$password_file" ] || die "There is no password in $password_file."
  virtualization=$(systemd-detect-virt || true)
  swap=$(swap_size "$(ram_gib)" "$hibernation")
  log "Installing on $disk, swap $swap, encryption $encrypt, hibernation $hibernation"

  step 2 "Writing the configuration"
  write_config "$stage" "$hardware_nix"

  step 3 "Checking the configuration before touching the disk"
  run nix eval --raw "$stage#nixosConfigurations.${DISTRO_ID}.config.system.build.toplevel.drvPath"
  echo

  step 4 "Partitioning and formatting $disk"
  mounted=1
  run disko --mode destroy,format,mount --yes-wipe-all-disks --flake "$stage#${DISTRO_ID}"
  shred_secrets_luks_only

  step 5 "Copying the configuration onto the disk"
  install -d -m 0755 /mnt/etc/nixos
  cp -a "$stage/." /mnt/etc/nixos/
  chown -R root:root /mnt/etc/nixos

  step 6 "Installing (this takes a while)"
  run nixos-install --root /mnt --flake "/mnt/etc/nixos#${DISTRO_ID}" --no-root-passwd --no-channel-copy

  step 7 "Setting the password"
  printf '%s:%s\n' "$user_name" "$(<"$password_file")" | nixos-enter --root /mnt -c chpasswd
  shred_secrets

  step 8 "Keeping the log"
  install -D -m 0600 "$log_file" "/mnt/var/log/${DISTRO_ID}-install.log"

  step 9 "Finishing"
  sync
  if [ "$unmount" -eq 1 ]; then
    release_disk
    mounted=0
  fi
  log "Done."
}

# The passphrase is only needed while formatting
shred_secrets_luks_only() {
  if [ -e "$luks_key_file" ]; then
    shred -u "$luks_key_file" 2>/dev/null || rm -f "$luks_key_file"
  fi
}
