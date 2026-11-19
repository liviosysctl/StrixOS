# The system monitor behind the load figures of the bar: btop in Ghostty, in the colors of the
# theme. A monitor that is already open gets the focus instead of a second window.
#   ID     the distribution's id (strix); the window's class is ID.monitor

class="$ID.monitor"
if hyprctl -j clients | jq -e --arg class "$class" 'any(.[]; .class == $class)' >/dev/null; then
    exec hyprctl dispatch "hl.dsp.focus({ window = \"class:^$class\$\" })"
fi

# The theme engine writes btop.theme next to Ghostty's colors: the session's, else the machine's.
# btop finds it as the theme "$ID" and reads it again on SIGUSR2, after every change of theme.
theme="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$ID/theme/btop.theme"
[ -f "$theme" ] || theme="/run/$ID/theme/btop.theme"
config="${XDG_CONFIG_HOME:-$HOME/.config}/btop"
mkdir -p "$config/themes"
ln -sfn "$theme" "$config/themes/$ID.theme"
if [ ! -f "$config/btop.conf" ]; then
    printf '%s\n' \
        "color_theme = \"$ID\"" \
        'theme_background = False' \
        'rounded_corners = False' \
        'graph_symbol = "braille"' >"$config/btop.conf"
else
    sed -i "s|^color_theme = .*|color_theme = \"$ID\"|" "$config/btop.conf"
fi

# A smaller type than the terminal's: btop needs 80 columns, also on a small or scaled screen
exec uwsm app -- ghostty --class="$class" --title="System monitor" --font-size=10 -e btop
