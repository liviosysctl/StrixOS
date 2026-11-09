# The console front end: one question per screen, then the install with a
# step list. Writes the answers file and the two secret files and hands over
# to the core.

ask_keyboard() {
  local choice
  draw_question 1 "Keyboard" "Which keyboard do you use?" "" \
    "Everything you type from here on uses it, the disk passphrase too."
  choice=$(gum choose --selected "Swiss German" "Swiss German" "Swiss French" "German" "French" "English (US)")
  keyboard_label=$choice
  case $choice in
    "Swiss German") keyboard=ch ;;
    "Swiss French") keyboard=ch-fr ;;
    "German") keyboard=de ;;
    "French") keyboard=fr ;;
    *) keyboard=us ;;
  esac
  # The initrd loads the same layout before it asks for the passphrase at boot
  loadkeys "$(keyboard_settings "$keyboard" | cut -d ' ' -f 1)" >/dev/null 2>&1 || true
}

ask_language() {
  local choice
  draw_question 2 "Language" "Which language should the system use?" "" \
    "Sets date, number and currency formats."
  choice=$(gum choose --selected "German (Switzerland)" "German (Switzerland)" "French (Switzerland)" \
    "Italian (Switzerland)" "German (Germany)" "English (UK)" "English (US)")
  locale_label=$choice
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
  draw_question 3 "Time zone" "Where are you?" ""
  time_zone=$(gum choose --selected "Europe/Zurich" "Europe/Zurich" "Somewhere else")
  if [ "$time_zone" = "Somewhere else" ]; then
    draw_question 3 "Time zone" "Search for a city" "" "Type to filter, Enter to pick."
    time_zone=$(timedatectl list-timezones | gum filter --placeholder "e.g. Berlin")
  fi
}

ask_you() {
  local error=""
  while true; do
    draw_question 4 "You" "What is your name?" "$error" "Shown at login."
    full_name=$(gum input --placeholder "Livio Muster" --char-limit 64)
    valid_full_name "$full_name" && break
    error="Please enter a name."
  done

  error=""
  while true; do
    draw_question 4 "You" "Pick a user name" "$error" \
      "Lowercase letters, digits, - and _. You log in with it."
    user_name=$(gum input --value "$(propose_user_name "$full_name")" --char-limit 32)
    valid_user_name "$user_name" && break
    error="\"$user_name\" does not work. Start with a letter and use only a-z, 0-9, - and _."
  done

  password=$(ask_secret 4 "You" "Choose a password" "For logging in and for sudo.")
  (
    umask 077
    printf '%s\n' "$password" >"$password_file"
  )
  unset password
}

# Asks twice until both entries match and are long enough, prints the result
ask_secret() {
  local index=$1 section=$2 question=$3 hint=$4 error="" first second
  while true; do
    draw_question "$index" "$section" "$question" "$error" "$hint" >&2
    first=$(gum input --password --placeholder "At least 8 characters")
    if [ "${#first}" -lt 8 ]; then
      error="At least 8 characters, please."
      continue
    fi
    draw_question "$index" "$section" "$question" "" "Once more, to rule out a typo." >&2
    second=$(gum input --password --placeholder "Again")
    [ "$first" = "$second" ] && break
    error="The two entries did not match. Try again."
  done
  printf '%s' "$first"
}

ask_computer_name() {
  local error=""
  while true; do
    draw_question 5 "Computer" "Name this computer" "$error" "How it appears on the network."
    host_name=$(gum input --value "$DISTRO_ID" --char-limit 63)
    valid_host_name "$host_name" && break
    error="Use lowercase letters, digits and - only."
  done
}

ask_disk() {
  local lines line path size model choice i
  local -a labels=() paths=()
  mapfile -t lines < <(candidate_disks)
  [ "${#lines[@]}" -gt 0 ] || die "No disk with at least 32 GiB found."

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r path size model _ <<<"$line"
    labels+=("$(printf '%-9s %6s GiB   %s' "${path##*/}" "$((size / 1073741824))" "${model:0:34}")")
    paths+=("$path")
  done

  draw_question 6 "Disk" "Where should ${DISTRO_NAME} go?" "" \
    "The whole disk is used and everything on it is deleted." \
    "Dual boot next to Windows is not supported."
  choice=$(gum choose "${labels[@]}")
  for i in "${!labels[@]}"; do
    if [ "${labels[$i]}" = "$choice" ]; then
      disk_device=${paths[$i]}
      disk_label=$(printf '%s, %s GiB, %s' "${paths[$i]##*/}" "$(($(disk_bytes "${paths[$i]}") / 1073741824))" "$(cut -f 3 <<<"${lines[$i]}")")
    fi
  done
  disk=$(stable_disk_path "$disk_device")
}

ask_encryption() {
  local passphrase
  draw_question 7 "Encryption" "Encrypt the disk?" "" \
    "Protects your files if the computer is stolen." \
    "You type a passphrase at every start."
  if gum confirm --default=true --affirmative "Encrypt" --negative "Don't encrypt" ""; then
    encrypt=true
    passphrase=$(ask_secret 7 "Encryption" "Choose a disk passphrase" \
      "Avoid y, z and special characters if you might change the keyboard later.")
    (
      umask 077
      printf '%s' "$passphrase" >"$luks_key_file"
    )
    unset passphrase
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
  draw_question 8 "Hibernation" "Allow hibernation?" "" \
    "Saves the open session to the disk and powers off completely." \
    "Takes a swap file as large as the memory, $(($(ram_gib) + 1)) GiB here."
  if gum confirm --default=$default --affirmative "Allow" --negative "No" ""; then
    hibernation=true
  else
    hibernation=false
  fi
}

summary_row() {
  printf '  %s%-15s%s %s\n' "$c_faint" "$1" "$c_reset" "$2"
}

confirm_summary() {
  local short typed error=""
  short=${disk_device##*/}
  while true; do
    draw_question 9 "Summary" "Check everything once more" "$error"
    summary_row "Keyboard" "$keyboard_label"
    summary_row "Language" "$locale_label"
    summary_row "Time zone" "$time_zone"
    summary_row "Name" "$full_name"
    summary_row "User name" "$user_name"
    summary_row "Computer" "$host_name"
    summary_row "Disk" "$disk_label"
    summary_row "Encryption" "$([ "$encrypt" = true ] && echo on || echo off)"
    summary_row "Hibernation" "$([ "$hibernation" = true ] && echo on || echo off)"
    printf '\n'
    lsblk --output NAME,SIZE,FSTYPE,LABEL "$disk_device" | sed "s/^/  ${c_faint}/; s/\$/${c_reset}/"
    printf '\n  %s%sEverything on %s will be deleted.%s\n' "$c_red" "$c_bold" "$short" "$c_reset"
    printf '  %sType %s to start, or leave it empty to cancel.%s\n\n' "$c_faint" "$short" "$c_reset"
    typed=$(gum input --placeholder "$short")
    [ -n "$typed" ] || die "Cancelled. Nothing was changed."
    [ "$typed" = "$short" ] && break
    error="That was not $short."
  done
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
  draw_header 0 "$question_total" "Network"
  printf '\n  %sNo internet connection%s\n' "$c_bold" "$c_reset"
  printf '  %sThe installation downloads part of the system.%s\n\n' "$c_faint" "$c_reset"
  if gum confirm --affirmative "Open network settings" --negative "Cancel" ""; then
    nmtui
  fi
  network_ok || die "Still no internet connection. Connect and start the installer again."
}

run_frontend() {
  ui_setup
  check_root
  check_uefi
  check_ram
  install -d -m 0700 "$work_dir"
  : >"$log_file"

  ensure_network
  ask_keyboard
  ask_language
  ask_time_zone
  ask_you
  ask_computer_name
  ask_disk
  ask_encryption
  ask_hibernation
  confirm_summary
  write_answers "$answers_file"

  install_from_answers "" 1

  draw_done
  if gum confirm --affirmative "Restart" --negative "Stay here" ""; then
    systemctl reboot
  fi
}
