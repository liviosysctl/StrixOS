# <id>-idle: what happens when nobody is at the machine, on power and on battery. The times are
# in ~/.config/<id>/idle.json (seconds, 0 for never); Settings › Power writes them.
#   run                      start hypridle with those times (the user service hypridle)
#   show                     the times as JSON, with the ones not set
#   set ac|battery ACTION N  change one and start again; ACTION is dim, lock, off or sleep
#   awake on|off|state       stay awake: nothing dims, locks or sleeps until it is turned off
#   do POWER ACTION          a time has passed (called by hypridle)
#   undo ACTION              somebody is back
#   ID  the distribution's id (strix)
usage() {
  echo "Usage: $(basename "$0") run|show|set ac|battery dim|lock|off|sleep SECONDS|awake on|off|state" >&2
  exit 64
}

file="${XDG_CONFIG_HOME:-$HOME/.config}/$ID/idle.json"
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$ID"
defaults='{"ac": {"dim": 240, "lock": 300, "off": 600, "sleep": 0},
  "battery": {"dim": 120, "lock": 300, "off": 600, "sleep": 900}}'

show() {
  if [ -r "$file" ] && jq -e . "$file" >/dev/null 2>&1; then
    jq -n --argjson defaults "$defaults" --slurpfile own "$file" '$defaults * $own[0]'
  else
    echo "$defaults" | jq .
  fi
}

# On battery: there is one and nothing feeds the machine
on_battery() {
  local supply
  for supply in /sys/class/power_supply/*/online; do
    [ -r "$supply" ] || continue
    if [ "$(cat "$supply")" = 1 ]; then return 1; fi
  done
  compgen -G "/sys/class/power_supply/BAT*" >/dev/null
}

case "${1:-}" in
  show)
    show
    ;;
  run)
    mkdir -p "$run"
    {
      echo "general {"
      echo "    lock_cmd = qs -c $ID ipc call lock lock"
      echo "    before_sleep_cmd = loginctl lock-session"
      echo "    after_sleep_cmd = $0 undo off"
      echo "}"
      show | jq -r --arg self "$0" '
        to_entries[] | .key as $power | .value | to_entries[] | select(.value > 0)
        | "listener {\n    timeout = \(.value)\n    on-timeout = \($self) do \($power) \(.key)"
          + (if .key == "dim" or .key == "off" then "\n    on-resume = \($self) undo \(.key)" else "" end)
          + "\n}"'
    } >"$run/hypridle.conf"
    exec hypridle -c "$run/hypridle.conf"
    ;;
  set)
    [ "$#" -eq 4 ] || usage
    case "$2" in ac | battery) ;; *) usage ;; esac
    case "$3" in dim | lock | off | sleep) ;; *) usage ;; esac
    case "$4" in "" | *[!0-9]*) usage ;; esac
    mkdir -p "${file%/*}"
    show | jq --arg power "$2" --arg action "$3" --argjson value "$4" '.[$power][$action] = $value' >"$file.new"
    mv -f "$file.new" "$file"
    if systemctl --user is-active --quiet hypridle.service; then
      systemctl --user restart hypridle.service
    fi
    ;;
  awake)
    # An inhibitor that hypridle honours; locking before sleep stays as it is
    case "${2:-state}" in
      state) if systemctl --user is-active --quiet "$ID-awake.service"; then echo on; else echo off; fi ;;
      on)
        systemctl --user is-active --quiet "$ID-awake.service" \
          || systemd-run --user --quiet --unit="$ID-awake" \
            systemd-inhibit --what=idle --who="$ID" --why="Stay awake" sleep infinity
        ;;
      off) systemctl --user stop "$ID-awake.service" 2>/dev/null || true ;;
      *) usage ;;
    esac
    ;;
  do)
    [ "$#" -eq 3 ] || usage
    if on_battery; then power=battery; else power=ac; fi
    [ "$2" = "$power" ] || exit 0
    case "$3" in
      dim)
        mkdir -p "$run"
        touch "$run/dimmed"
        brightnessctl -q -s -c backlight set 30% || true
        ;;
      lock) loginctl lock-session ;;
      off) hyprctl dispatch 'hl.dsp.dpms({action = "off"})' ;;
      sleep) systemctl suspend ;;
      *) usage ;;
    esac
    ;;
  undo)
    case "${2:-}" in
      dim)
        if [ -e "$run/dimmed" ]; then
          rm -f "$run/dimmed"
          brightnessctl -q -r -c backlight || true
        fi
        ;;
      off) hyprctl dispatch 'hl.dsp.dpms({action = "on"})' ;;
      *) usage ;;
    esac
    ;;
  *)
    usage
    ;;
esac
