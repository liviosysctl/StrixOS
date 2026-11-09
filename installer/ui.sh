# Look of the interactive installer: black, red, and white only where it
# matters (the question and what the user typed). Everything is left-aligned
# like the Strix documents.
#
# The colors depend on the terminal: the console of the live system knows 16
# colors, an SSH session from Windows Terminal knows 256 or true color.
#
# Only characters that both Linux console fonts (the kernel's default8x16 and
# Lat2-Terminus16) contain: █ ─ ■ » · and ASCII. Anything else shows up as a
# placeholder box on the console of the live system.

ui_fancy=0

ui_setup() {
  ui_fancy=1
  local accent="#C8102E"

  if [[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]]; then
    c_red=$'\e[38;2;200;16;46m'
    c_faint=$'\e[38;2;128;128;128m'
  elif [[ ${TERM:-} == *256color* ]]; then
    c_red=$'\e[38;5;160m'
    c_faint=$'\e[38;5;244m'
  else
    c_red=$'\e[31m'
    c_faint=$'\e[2m'
    # Same red as the logo, not the bright red gum would pick for the hex value
    accent=1
  fi
  c_bold=$'\e[1m'
  c_reset=$'\e[0m'

  # gum reads its style from the environment
  export GUM_CHOOSE_CURSOR="» "
  export GUM_CHOOSE_CURSOR_FOREGROUND=$accent
  export GUM_CHOOSE_SELECTED_FOREGROUND=$accent
  export GUM_CHOOSE_PADDING="0 0 0 2"
  export GUM_CHOOSE_SHOW_HELP=false
  export GUM_CHOOSE_HEADER=""

  export GUM_INPUT_PROMPT="» "
  export GUM_INPUT_PROMPT_FOREGROUND=$accent
  export GUM_INPUT_CURSOR_FOREGROUND=$accent
  export GUM_INPUT_PLACEHOLDER_FOREGROUND=8
  export GUM_INPUT_PADDING="0 0 0 2"
  export GUM_INPUT_WIDTH=48
  export GUM_INPUT_SHOW_HELP=false

  export GUM_CONFIRM_PROMPT_FOREGROUND=7
  export GUM_CONFIRM_SELECTED_BACKGROUND=$accent
  export GUM_CONFIRM_SELECTED_FOREGROUND=0
  export GUM_CONFIRM_UNSELECTED_BACKGROUND=0
  export GUM_CONFIRM_UNSELECTED_FOREGROUND=8
  export GUM_CONFIRM_PADDING="0 0 0 2"
  export GUM_CONFIRM_SHOW_HELP=false

  export GUM_FILTER_INDICATOR="»"
  export GUM_FILTER_INDICATOR_FOREGROUND=$accent
  export GUM_FILTER_MATCH_FOREGROUND=$accent
  export GUM_FILTER_PROMPT="» "
  export GUM_FILTER_PROMPT_FOREGROUND=$accent
  export GUM_FILTER_PADDING="0 0 0 2"
  export GUM_FILTER_HEIGHT=10
  export GUM_FILTER_SHOW_HELP=false

  # Braille spinners do not exist in the console fonts
  export GUM_SPIN_SPINNER=line
  export GUM_SPIN_SPINNER_FOREGROUND=$accent
  export GUM_SPIN_PADDING="0 0 0 2"
}

repeat() {
  local text=$1 count=$2 out=""
  while [ "$count" -gt 0 ]; do
    out+=$text
    count=$((count - 1))
  done
  printf '%s' "$out"
}

draw_logo() {
  local line out i
  while IFS= read -r line; do
    out="  ${c_red}"
    for ((i = 0; i < ${#line}; i++)); do
      if [ "${line:i:1}" = "#" ]; then
        out+="██"
      else
        out+="  "
      fi
    done
    printf '%s%s\n' "$out" "$c_reset"
  done <"$LOGO_FILE"
}

# Width of the logo in terminal cells, the bar below has the same width
logo_width() {
  local line longest=0
  while IFS= read -r line; do
    [ "${#line}" -gt "$longest" ] && longest=${#line}
  done <"$LOGO_FILE"
  echo $((longest * 2))
}

# The header: the name in block letters, below it a thin line that fills in
# red as the installation goes on (like the boot splash), then the step.
#
#   ██  ██████ ...
#   ──────────────────────────────────────────
#   3/9  Time zone                Installer 0.1.0
draw_header() {
  local done=$1 total=$2 title=$3 rows width filled left right gap
  rows=$(tput lines 2>/dev/null || echo 24)
  width=$(logo_width)
  printf '\e[2J\e[H\n'
  if [ "$rows" -ge 30 ]; then
    draw_logo
  else
    printf '  %s%s%s%s\n' "$c_red" "$c_bold" "${DISTRO_NAME^^}" "$c_reset"
  fi
  printf '\n'

  filled=$((width * done / total))
  printf '  %s%s%s%s%s\n' "$c_red" "$(repeat ─ "$filled")" "$c_faint" "$(repeat ─ $((width - filled)))" "$c_reset"

  left="$done/$total  $title"
  right="Installer $DISTRO_VERSION"
  gap=$((width - ${#left} - ${#right}))
  [ "$gap" -ge 2 ] || gap=2
  printf '  %s%s/%s%s  %s%s%s%s\n\n' "$c_faint" "$done" "$total" "$c_reset" "$title" \
    "$(repeat " " "$gap")" "$c_faint$right" "$c_reset"
}

# One question per screen: header, progress, the question in bold, hints in
# faint, an error in red if the last answer did not work
question_total=9

draw_question() {
  local index=$1 section=$2 question=$3 error=$4 line
  shift 4
  draw_header "$index" "$question_total" "$section"
  printf '\n  %s%s%s\n' "$c_bold" "$question" "$c_reset"
  for line in "$@"; do
    printf '  %s%s%s\n' "$c_faint" "$line" "$c_reset"
  done
  if [ -n "$error" ]; then
    printf '  %s%s%s\n' "$c_red" "$error" "$c_reset"
  fi
  printf '\n'
}

# The install steps as a list: ■ done, » running, · still to come
draw_install() {
  local current=$1 i title
  draw_header $((current - 1)) "$total_steps" "Installing"
  printf '\n'
  for i in "${!install_steps[@]}"; do
    title=${install_steps[$i]}
    if [ $((i + 1)) -lt "$current" ]; then
      printf '  %s■%s %s%s%s\n' "$c_red" "$c_reset" "$c_faint" "$title" "$c_reset"
    elif [ $((i + 1)) -eq "$current" ]; then
      printf '  %s»%s %s%s%s\n' "$c_red" "$c_reset" "$c_bold" "$title" "$c_reset"
    else
      printf '  %s· %s%s\n' "$c_faint" "$title" "$c_reset"
    fi
  done
  printf '\n'
}

# Runs a command behind a spinner, its output only goes to the log.
# The title says what to expect, the step itself is already in the list.
spin() {
  local title=$1
  shift
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  gum spin --title "$title" -- "$BASH" -c '"$@" >>"$0" 2>&1' "$log_file" "$@"
}

draw_failure() {
  printf '\n  %s%sInstallation failed.%s\n' "$c_red" "$c_bold" "$c_reset"
  printf '  %sThe disk may be partly written. Nothing is lost by starting the installer again.%s\n\n' "$c_faint" "$c_reset"
  tail -n 12 "$log_file" | sed "s/^/    ${c_faint}/; s/\$/${c_reset}/"
  printf '\n  %sFull log: %s%s\n\n' "$c_faint" "$log_file" "$c_reset"
}

draw_done() {
  draw_header "$total_steps" "$total_steps" "Done"
  printf '\n  %s■%s %s%s is installed.%s\n' "$c_red" "$c_reset" "$c_bold" "$DISTRO_NAME" "$c_reset"
  printf '  %sRemove the USB stick, then restart.%s\n' "$c_faint" "$c_reset"
  if [ "${encrypt:-false}" = true ]; then
    printf '  %sAt every start you type the disk passphrase first.%s\n' "$c_faint" "$c_reset"
  fi
  printf '\n'
}
