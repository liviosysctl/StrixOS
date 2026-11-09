# The console front end: one question per screen, then the install with a
# step list. Writes the answers file and the two secret files and hands over
# to the core.

# The language comes first and switches the installer to it. Each language
# is named in itself, the rest of the screen is in the default language.
languages=(
  en_US.UTF-8 "English (US)"
  en_GB.UTF-8 "English (UK)"
  de_CH.UTF-8 "Deutsch (Schweiz)"
  de_DE.UTF-8 "Deutsch (Deutschland)"
  fr_CH.UTF-8 "Français (Suisse)"
  it_CH.UTF-8 "Italiano (Svizzera)"
)
default_locale=en_US.UTF-8

# pick DEFAULT KEY LABEL KEY LABEL ... shows the labels and prints the key of
# the chosen one
pick() {
  local default=$1 selected="" choice i
  shift
  local -a keys=() labels=()
  while [ "$#" -gt 1 ]; do
    keys+=("$1")
    labels+=("$2")
    shift 2
  done
  for i in "${!keys[@]}"; do
    [ "${keys[$i]}" = "$default" ] && selected=${labels[$i]}
  done
  choice=$(gum choose --selected "$selected" "${labels[@]}")
  for i in "${!labels[@]}"; do
    if [ "${labels[$i]}" = "$choice" ]; then
      printf '%s' "${keys[$i]}"
      return 0
    fi
  done
  return 1
}

# Label of a key in a KEY LABEL list
label_of() {
  local key=$1
  shift
  while [ "$#" -gt 1 ]; do
    if [ "$1" = "$key" ]; then
      printf '%s' "$2"
      return 0
    fi
    shift 2
  done
  return 1
}

ask_language() {
  ui_lang=$(ui_lang_for_locale "$default_locale")
  draw_question 1 "$(t s_language)" "$(t q_language)" "" "$(t h_language)"
  locale=$(pick "$default_locale" "${languages[@]}")
  locale_label=$(label_of "$locale" "${languages[@]}")
  ui_lang=$(ui_lang_for_locale "$locale")
}

# The keyboard most people with this language use
default_keyboard() {
  case $1 in
    de_CH.* | it_CH.*) echo ch ;;
    fr_CH.*) echo ch-fr ;;
    de_DE.*) echo de ;;
    en_GB.*) echo gb ;;
    *) echo us ;;
  esac
}

keyboards() {
  printf '%s\n' \
    ch "$(t kb_ch)" \
    ch-fr "$(t kb_ch_fr)" \
    de "$(t kb_de)" \
    fr "$(t kb_fr)" \
    it "$(t kb_it)" \
    gb "$(t kb_gb)" \
    us "$(t kb_us)"
}

ask_keyboard() {
  local -a list
  mapfile -t list < <(keyboards)
  draw_question 2 "$(t s_keyboard)" "$(t q_keyboard)" "" "$(t h_keyboard)"
  keyboard=$(pick "$(default_keyboard "$locale")" "${list[@]}")
  keyboard_label=$(label_of "$keyboard" "${list[@]}")
  # The initrd loads the same layout before it asks for the passphrase at boot
  loadkeys "$(keyboard_settings "$keyboard" | cut -d ' ' -f 1)" >/dev/null 2>&1 || true
}

default_time_zone() {
  case $1 in
    de_DE.*) echo Europe/Berlin ;;
    en_GB.*) echo Europe/London ;;
    *) echo Europe/Zurich ;;
  esac
}

ask_time_zone() {
  local zone
  zone=$(default_time_zone "$locale")
  draw_question 3 "$(t s_timezone)" "$(t q_timezone)" ""
  time_zone=$(pick "$zone" "$zone" "$zone" other "$(t tz_other)")
  if [ "$time_zone" = other ]; then
    draw_question 3 "$(t s_timezone)" "$(t q_tz_search)" "" "$(t h_tz_search)"
    time_zone=$(timedatectl list-timezones | gum filter --placeholder "$(t ph_tz)")
  fi
}

ask_you() {
  local error=""
  while true; do
    draw_question 4 "$(t s_you)" "$(t q_name)" "$error" "$(t h_name)"
    full_name=$(gum input --placeholder "Livio Muster" --char-limit 64)
    valid_full_name "$full_name" && break
    error=$(t e_name)
  done

  error=""
  while true; do
    draw_question 4 "$(t s_you)" "$(t q_user)" "$error" "$(t h_user)"
    user_name=$(gum input --value "$(propose_user_name "$full_name")" --char-limit 32)
    valid_user_name "$user_name" && break
    error=$(tf e_user "$user_name")
  done

  password=$(ask_secret 4 "$(t s_you)" "$(t q_password)" "$(t h_password)")
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
    first=$(gum input --password --placeholder "$(t ph_secret)")
    if [ "${#first}" -lt 8 ]; then
      error=$(t e_short)
      continue
    fi
    draw_question "$index" "$section" "$question" "" "$(t h_again)" >&2
    second=$(gum input --password --placeholder "$(t ph_again)")
    [ "$first" = "$second" ] && break
    error=$(t e_mismatch)
  done
  printf '%s' "$first"
}

ask_computer_name() {
  local error=""
  while true; do
    draw_question 5 "$(t s_computer)" "$(t q_computer)" "$error" "$(t h_computer)"
    host_name=$(gum input --value "$DISTRO_ID" --char-limit 63)
    valid_host_name "$host_name" && break
    error=$(t e_computer)
  done
}

ask_disk() {
  local lines line path size model choice i
  local -a labels=() paths=()
  mapfile -t lines < <(candidate_disks)
  [ "${#lines[@]}" -gt 0 ] || die "$(t e_no_disk)"

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r path size model _ <<<"$line"
    labels+=("$(printf '%-9s %6s GiB   %s' "${path##*/}" "$((size / 1073741824))" "${model:0:34}")")
    paths+=("$path")
  done

  draw_question 6 "$(t s_disk)" "$(tf q_disk "$DISTRO_NAME")" "" \
    "$(t h_disk_whole)" "$(t h_disk_dual)"
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
  draw_question 7 "$(t s_encryption)" "$(t q_encrypt)" "" \
    "$(t h_encrypt_why)" "$(t h_encrypt_cost)"
  if gum confirm --default=true --affirmative "$(t b_encrypt)" --negative "$(t b_no_encrypt)" ""; then
    encrypt=true
    passphrase=$(ask_secret 7 "$(t s_encryption)" "$(t q_passphrase)" "$(t h_passphrase)")
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
  draw_question 8 "$(t s_hibernation)" "$(t q_hibernate)" "" \
    "$(t h_hibernate_what)" "$(tf h_hibernate_cost $(($(ram_gib) + 1)))"
  if gum confirm --default=$default --affirmative "$(t b_allow)" --negative "$(t b_no)" ""; then
    hibernation=true
  else
    hibernation=false
  fi
}

summary_row() {
  printf '  %s%s%s %s\n' "$c_faint" "$(pad "$(t "$1")" 16)" "$c_reset" "$2"
}

on_off() {
  if [ "$1" = true ]; then t v_on; else t v_off; fi
}

confirm_summary() {
  local short typed error=""
  short=${disk_device##*/}
  while true; do
    draw_question 9 "$(t s_summary)" "$(t q_summary)" "$error"
    summary_row l_language "$locale_label"
    summary_row l_keyboard "$keyboard_label"
    summary_row l_timezone "$time_zone"
    summary_row l_name "$full_name"
    summary_row l_user "$user_name"
    summary_row l_computer "$host_name"
    summary_row l_disk "$disk_label"
    summary_row l_encryption "$(on_off "$encrypt")"
    summary_row l_hibernation "$(on_off "$hibernation")"
    printf '\n'
    lsblk --output NAME,SIZE,FSTYPE,LABEL "$disk_device" | sed "s/^/  ${c_faint}/; s/\$/${c_reset}/"
    printf '\n  %s%s%s%s\n' "$c_accent" "$c_bold" "$(tf w_deleted "$short")" "$c_reset"
    printf '  %s%s%s\n\n' "$c_faint" "$(tf h_type "$short")" "$c_reset"
    typed=$(gum input --placeholder "$short")
    [ -n "$typed" ] || die "$(t cancelled)"
    [ "$typed" = "$short" ] && break
    error=$(tf e_typed "$short")
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
  draw_header 2 "$question_total" "$(t s_network)"
  printf '\n  %s%s%s\n' "$c_bold" "$(t q_network)" "$c_reset"
  printf '  %s%s%s\n\n' "$c_faint" "$(t h_network)" "$c_reset"
  if gum confirm --affirmative "$(t b_network)" --negative "$(t b_cancel)" ""; then
    nmtui
  fi
  network_ok || die "$(t e_network)"
}

run_frontend() {
  ui_setup
  ask_language
  check_root
  check_uefi
  check_ram
  install -d -m 0700 "$work_dir"
  : >"$log_file"

  ask_keyboard
  # After the keyboard, so a Wi-Fi password is typed with the right layout
  ensure_network
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
  if gum confirm --affirmative "$(t b_restart)" --negative "$(t b_stay)" ""; then
    systemctl reboot
  fi
}
