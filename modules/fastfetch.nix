# fastfetch with the owl of the distro, for every user (/etc/xdg/fastfetch/config.jsonc).
# The logo is the full owl as an image, the frames' titles in the accent: both follow the theme.
# `fastfetch` is a wrapper that reads the current theme from tokens.json (the session's, else the
# machine's) and passes its owl and accent; without one it shows the default theme. Ghostty shows
# the image through the kitty image protocol. Whoever has an own fastfetch config gets it as is.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  theme = config.${id}.theme;
  look = theme.defaultLook;
  accent = look.colors.accent or "red";
  logos = theme.logos;

  real = lib.getExe pkgs.fastfetch;
  wrapper = pkgs.writeShellScriptBin "fastfetch" ''
    own="''${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
    if [ -e "$own/config.jsonc" ] || [ -e "$own/config.json" ]; then
      exec ${real} "$@"
    fi
    args=()
    # Ghostty and kitty read the owl straight from its file, the console of the kernel shows none
    case "''${TERM:-}" in
      xterm-ghostty | xterm-kitty) args+=(--logo-type kitty-direct) ;;
      linux | dumb) args+=(--logo-type none) ;;
    esac
    for dir in ''${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR/${id}/theme"} /run/${id}/theme; do
      [ -r "$dir/tokens.json" ] || continue
      if read -r name variant color < <(${lib.getExe pkgs.jq} -er \
        '[.theme, .variant, .colors.accent] | join(" ")' "$dir/tokens.json" 2>/dev/null); then
        logo=${logos}/$name-$variant.png
        [ -f "$logo" ] && args+=(--logo "$logo")
        args+=(--color-title "$color" --bar-color-elapsed "$color")
      fi
      break
    done
    exec ${real} "''${args[@]}" "$@"
  '';

  # Width of the frames in columns
  width = 50;
  line = n: lib.concatStrings (lib.replicate n "─");
  frameTop =
    title:
    let
      rest = width - 4 - lib.stringLength title;
      left = rest / 2;
    in
    {
      type = "custom";
      format = "{#bright_black}┌${line left} {#title}${title}{#bright_black} ${line (rest - left)}┐";
    };
  frameBottom = {
    type = "custom";
    format = "{#bright_black}└${line (width - 2)}┘";
  };
  # Keys padded by hand, so the :: stand in one column
  pad = name: "  " + name + lib.concatStrings (lib.replicate (9 - lib.stringLength name) " ");
  entry = type: name: extra: { inherit type; key = pad name; } // extra;
in
# The owls come from the theme engine
lib.mkIf theme.enable {
  # The wrapper first: its bin/fastfetch wins over the one of the package
  environment.systemPackages = [
    (pkgs.symlinkJoin {
      name = "fastfetch-${id}";
      paths = [
        wrapper
        pkgs.fastfetch
      ];
      meta.mainProgram = "fastfetch";
    })
  ];

  environment.etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
    logo = {
      type = "auto";
      source = "${logos}/${look.theme or ""}-${look.variant or ""}.png";
      width = 36;
      height = 18;
      padding.right = 4;
    };
    display = {
      separator = " :: ";
      color = {
        keys = "default";
        title = accent;
        separator = "bright_black";
        output = "default";
      };
      # One accent: bars in the accent, numbers only turn red when nearly full
      percent = {
        type = 3;
        color = {
          green = "default";
          yellow = "default";
          red = "red";
        };
      };
      bar = {
        char = {
          elapsed = "■";
          total = "·";
        };
        width = 10;
        border = {
          left = "";
          right = "";
        };
        color = {
          elapsed = accent;
          total = "bright_black";
        };
      };
      size = {
        binaryPrefix = "iec";
        ndigits = 1;
      };
    };
    modules = [
      {
        type = "title";
        format = "{#title}{user-name}{#}{#bright_black} @ {#}{host-name}";
      }
      "break"
      (frameTop "Software")
      (entry "os" "System" { format = "{pretty-name} {arch}"; })
      (entry "kernel" "Kernel" { format = "{release}"; })
      (entry "wm" "Desktop" { })
      (entry "terminal" "Terminal" { })
      (entry "shell" "Shell" { })
      (entry "packages" "Packages" { })
      frameBottom
      "break"
      (frameTop "Hardware")
      (entry "host" "Machine" { })
      (entry "cpu" "Processor" { format = "{name} ({cores-physical}C/{cores-logical}T)"; })
      (entry "gpu" "Graphics" { format = "{name}"; })
      (entry "memory" "Memory" { format = "{percentage-bar} {percentage}  {used} / {total}"; })
      (entry "disk" "Disk" {
        folders = "/";
        format = "{size-percentage-bar} {size-percentage}  {size-used} / {size-total}";
      })
      frameBottom
      "break"
      (frameTop "Status")
      (entry "command" "Installed" {
        # Birth time of /, the day of the installation
        text = ''d=$(stat -c %W /); [ "$d" -gt 0 ] && echo "$(date -d @$d +%Y-%m-%d), $(( ($(date +%s) - d) / 86400 )) days ago"'';
      })
      (entry "uptime" "Uptime" { })
      frameBottom
    ];
  };
}
