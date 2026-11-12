# <id>-capture region|window|screen|record|colour: screenshots, a screen recording and the colour
# picker of the cheat sheet (Print, Shift Print, Ctrl Print, Alt Print, Super Print).
#
# Screenshots go to ~/Pictures/Screenshots and to the clipboard, recordings to ~/Videos/Recordings;
# a notification says where. Alt Print a second time stops the recording.
usage() {
  echo "Usage: $(basename "$0") region|window|screen|record|colour" >&2
  exit 64
}

stamp=$(date +%Y-%m-%d_%H-%M-%S)
shots="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
videos="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"

shot() {
  local file="$shots/$stamp.png"
  mkdir -p "$shots"
  grim "$@" "$file"
  wl-copy --type image/png <"$file"
  notify-send --app-name=Capture --icon="$file" "Screenshot" "In the clipboard and in $file"
}

case "${1:-}" in
  region)
    # Esc in slurp is not an error worth a message
    area=$(slurp -d) || exit 0
    shot -g "$area"
    ;;
  window)
    area=$(hyprctl -j activewindow | jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')
    if [ -z "$area" ]; then
      notify-send --app-name=Capture "Screenshot" "No window has the focus"
      exit 1
    fi
    shot -g "$area"
    ;;
  screen)
    shot
    ;;
  record)
    if pkill -INT -x wf-recorder; then
      notify-send --app-name=Capture "Recording stopped" "In $videos"
      exit 0
    fi
    area=$(slurp -d) || exit 0
    mkdir -p "$videos"
    notify-send --app-name=Capture "Recording" "Alt Print stops it"
    exec wf-recorder -g "$area" -f "$videos/$stamp.mp4"
    ;;
  colour)
    colour=$(hyprpicker --autocopy --format=hex) || exit 0
    [ -n "$colour" ] && notify-send --app-name=Capture "Colour $colour" "In the clipboard"
    ;;
  *)
    usage
    ;;
esac
