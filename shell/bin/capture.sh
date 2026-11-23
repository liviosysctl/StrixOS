# <id>-capture region|window|screen|annotate|text|record|record-screen|stop|colour: screenshots,
# screen recordings and the colour picker of the cheat sheet (Print, Shift Print, Ctrl Print,
# Alt Print, Ctrl Alt Print, Super Print). annotate opens a region in Satty to draw and write on
# before it is saved (Ctrl Shift Print); text reads the words in a region and puts them into the
# clipboard (Super Shift Print).
#
# Screenshots go to ~/Pictures/Screenshots and to the clipboard, recordings to ~/Videos/Recordings;
# a notification says where. Either recording key a second time, or the red mark the bar shows
# while it runs, stops the recording (stop).
#
# Choosing a region takes the keyboard, and what the shell has open over the desktop (the search,
# the theme picker, a panel of the bar) closes when it loses it. So the screen is frozen first:
# the region is chosen on a still picture of everything that was there, and that is what is saved.
usage() {
  echo "Usage: $(basename "$0") region|window|screen|annotate|text|record|record-screen|stop|colour" >&2
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

# A still picture of every screen over everything, until thaw
freeze() {
  hyprpicker -r -z >/dev/null 2>&1 &
  frozen=$!
  # until it is on the screen
  sleep 0.2
}
thaw() {
  kill "$frozen" 2>/dev/null || true
}

# The region chosen on the frozen screen, or nothing after Esc, which is not an error worth a message
region() {
  freeze
  area=$(slurp -d) || {
    thaw
    exit 0
  }
}

case "${1:-}" in
  region)
    region
    shot -g "$area"
    thaw
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
  annotate)
    region
    mkdir -p "$shots"
    picture=$(mktemp --suffix=.png)
    grim -g "$area" "$picture"
    thaw
    satty --filename "$picture" --output-filename "$shots/$stamp.png" \
      --copy-command wl-copy --early-exit --initial-tool arrow
    rm -f "$picture"
    ;;
  text)
    region
    picture=$(mktemp --suffix=.png)
    grim -g "$area" "$picture"
    thaw
    words=$(tesseract "$picture" stdout -l eng+deu+fra+ita 2>/dev/null | sed '/^[[:space:]]*$/d') || true
    rm -f "$picture"
    if [ -z "$words" ]; then
      notify-send --app-name=Capture "No text found" "Nothing readable in that region"
      exit 0
    fi
    printf '%s' "$words" | wl-copy
    notify-send --app-name=Capture "Text copied" "$(printf '%s' "$words" | head -n 3)"
    ;;
  record | record-screen | stop)
    if pkill -INT -x wf-recorder; then
      notify-send --app-name=Capture "Recording stopped" "In $videos"
      exit 0
    fi
    [ "$1" = stop ] && exit 0
    if [ "$1" = record ]; then
      area=$(slurp -d) || exit 0
      where=(-g "$area")
    else
      # The screen that has the focus
      where=(-o "$(hyprctl -j monitors | jq -r 'map(select(.focused)) | .[0].name')")
    fi
    mkdir -p "$videos"
    notify-send --app-name=Capture "Recording" "The same key again, or the red mark in the bar, stops it"
    exec wf-recorder "${where[@]}" -f "$videos/$stamp.mp4"
    ;;
  colour)
    colour=$(hyprpicker --autocopy --format=hex) || exit 0
    [ -n "$colour" ] && notify-send --app-name=Capture "Colour $colour" "In the clipboard"
    ;;
  *)
    usage
    ;;
esac
