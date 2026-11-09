# The text front end: asks the questions, writes the answers file and the
# two secret files, then hands over to the core.

heading() {
  gum style --bold --margin "1 0 0 0" "$1"
}

hint() {
  gum style --faint "$1"
}

ask_keyboard() {
  local choice
  heading "Keyboard"
  choice=$(gum choose --selected "Swiss German" "Swiss German" "Swiss French" "German" "French" "English (US)")
  case $choice in
    "Swiss German") keyboard=ch ;;
    "Swiss French") keyboard=ch-fr ;;
    "German") keyboard=de ;;
    "French") keyboard=fr ;;
    *) keyboard=us ;;
  esac
  # From here on everything typed uses this layout, the disk passphrase
  # included. The initrd loads the same layout before it asks at boot.
  loadkeys "$(keyboard_settings "$keyboard" | cut -d ' ' -f 1)" >/dev/null 2>&1 || true
}

ask_language() {
  local choice
  heading "Language"
  choice=$(gum choose --selected "German (Switzerland)" "German (Switzerland)" "French (Switzerland)" \
    "Italian (Switzerland)" "German (Germany)" "English (UK)" "English (US)")
  case $choice in
    "German (Switzerland)") locale=de_CH.UTF-8 ;;
    "French (Switzerland)") locale=fr_CH.UTF-8 ;;
    "Italian (Switzerland)") locale=it_CH.UTF-8 ;;
    "German (Germany)") locale=de_DE.UTF-8 ;;
    "English (UK)") locale=en_GB.UTF-8 ;;
    *) locale=en_US.UTF-8 ;;
  esac
}

ask_time_zone() {
  heading "Time zone"
  time_zone=$(gum choose --selected "Europe/Zurich" "Europe/Zurich" "Other...")
  if [ "$time_zone" = "Other..." ]; then
    time_zone=$(timedatectl list-timezones | gum filter --placeholder "Search for a city")
  fi
}

ask_names() {
  heading "Your name"
  hint "Shown at login."
  while true; do
    full_name=$(gum input --placeholder "Livio Muster" --char-limit 64)
    valid_full_name "$full_name" && break
    hint "Please enter a name."
  done

  heading "User name"
  hint "Lowercase letters, digits, - and _. Used to log in."
  while true; do
    user_name=$(gum input --value "$(propose_user_name "$full_name")" --char-limit 32)
    valid_user_name "$user_name" && break
    hint "\"$user_name\" is not possible. Start with a letter, use only a-z, 0-9, - and _."
  done

  heading "Computer name"
  hint "How this computer appears on the network."
  while true; do
    host_name=$(gum input --value "$DISTRO_ID" --char-limit 63)
    valid_host_name "$host_name" && break
    hint "Use lowercase letters, digits and - only."
  done
}

# Asks twice until both match and are long enough, prints the result
ask_secret() {
  local label=$1 first second
  while true; do
    first=$(gum input --password --header "$label")
    if [ "${#first}" -lt 8 ]; then
      hint "At least 8 characters, please." >&2
      continue
    fi
    second=$(gum input --password --header "$label again")
    [ "$first" = "$second" ] && break
    hint "The two entries do not match." >&2
  done
  printf '%s' "$first"
}

ask_password() {
  local password
  heading "Password"
  hint "For logging in and for sudo."
  password=$(ask_secret "Password")
  (
    umask 077
    printf '%s\n' "$password" >"$password_file"
  )
}

ask_disk() {
  local lines line path size model tran label choice
  local -a labels=() paths=()
  mapfile -t lines < <(candidate_disks)
  [ "${#lines[@]}" -gt 0 ] || die "No disk with at least 32 GiB found."

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r path size model tran <<<"$line"
    label="$model, $((size / 1073741824)) GiB${tran:+, ${tran^^}} (${path##*/})"
    labels+=("$label")
    paths+=("$path")
  done

  heading "Disk"
  hint "Everything on the chosen disk will be deleted. Dual boot is not supported."
  choice=$(gum choose "${labels[@]}")
  for i in "${!labels[@]}"; do
    if [ "${labels[$i]}" = "$choice" ]; then
      disk_device=${paths[$i]}
    fi
  done
  disk=$(stable_disk_path "$disk_device")
}

ask_encryption() {
  local passphrase
  heading "Encryption"
  hint "Protects your files if the computer is stolen. You type a passphrase at every start."
  if gum confirm --default=true "Encrypt the disk?"; then
    encrypt=true
    hint "Avoid letters that move between keyboard layouts (y, z, special characters) if you ever change the layout."
    passphrase=$(ask_secret "Disk passphrase")
    (
      umask 077
      printf '%s' "$passphrase" >"$luks_key_file"
    )
  else
    encrypt=false
  fi
}

ask_hibernation() {
  local disk_gib default=false
  disk_gib=$(($(disk_bytes "$disk_device") / 1073741824))
  if ! hibernation_fits "$disk_gib" "$(ram_gib)"; then
    hibernation=false
    return
  fi
  is_laptop && default=true
  heading "Hibernation"
  hint "Saves the open session to the disk and powers off completely. Needs a swap file as large as the RAM."
  if gum confirm --default=$default "Allow hibernation?"; then
    hibernation=true
  else
    hibernation=false
  fi
}

confirm_summary() {
  local short typed
  short=${disk_device##*/}
  heading "Summary"
  gum style --border normal --padding "0 1" \
    "Keyboard        $keyboard" \
    "Language        $locale" \
    "Time zone       $time_zone" \
    "Name            $full_name" \
    "User name       $user_name" \
    "Computer name   $host_name" \
    "Disk            $disk" \
    "Encryption      $encrypt" \
    "Hibernation     $hibernation"

  echo
  lsblk --output NAME,SIZE,FSTYPE,LABEL "$disk_device"
  echo
  gum style --bold --foreground 1 "Everything on $short will be deleted, including Windows if it is there."
  typed=$(gum input --header "Type $short to start the installation" --placeholder "$short")
  [ "$typed" = "$short" ] || die "Cancelled. Nothing was changed."
}

write_answers() {
  jq -n \
    --arg hostName "$host_name" \
    --arg timeZone "$time_zone" \
    --arg locale "$locale" \
    --arg keyboard "$keyboard" \
    --arg userName "$user_name" \
    --arg fullName "$full_name" \
    --arg disk "$disk" \
    --argjson encrypt "$encrypt" \
    --argjson hibernation "$hibernation" \
    '{
      hostName: $hostName,
      timeZone: $timeZone,
      locale: $locale,
      keyboard: $keyboard,
      user: { name: $userName, fullName: $fullName },
      disk: $disk,
      encrypt: $encrypt,
      hibernation: $hibernation
    }' >"$1"
}

ensure_network() {
  network_ok && return 0
  heading "No internet connection"
  hint "The installation downloads part of the system."
  if gum confirm "Open the network settings?"; then
    nmtui
  fi
  network_ok || die "Still no internet connection. Connect and start the installer again."
}

run_frontend() {
  local answers_file="$work_dir/answers.json"
  check_root
  check_uefi
  check_ram
  install -d -m 0700 "$work_dir"

  gum style --bold --margin "1 0" "${DISTRO_NAME} ${DISTRO_VERSION} installer"
  ensure_network
  ask_keyboard
  ask_language
  ask_time_zone
  ask_names
  ask_password
  ask_disk
  ask_encryption
  ask_hibernation
  confirm_summary
  write_answers "$answers_file"

  install_from_answers "" 1

  echo
  gum style --bold "${DISTRO_NAME} is installed. Remove the USB stick, then restart."
  if gum confirm "Restart now?"; then
    systemctl reboot
  fi
}
