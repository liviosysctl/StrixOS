# fastfetch with the owl of the distro, for every user (/etc/xdg/fastfetch/config.jsonc).
# The logo is the full owl as an image; the layout is the one of the configuration Strix grew out
# of: three ruled sections (Hardware, Software, Uptime / Age), keys with a symbol in the colors
# of the terminal, which follow the theme. In a narrow terminal the owl goes above the text.
# `fastfetch` is a wrapper that reads the current theme from tokens.json (the session's, else the
# machine's) and passes its owl; without one it shows the default theme. Ghostty shows
# the image through the kitty image protocol. Whoever has an own fastfetch config gets it as is.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  theme = config.${id}.theme;
  look = theme.defaultLook;
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
    # Owl and text side by side need about 90 columns: in less (half a screen) the owl goes on top
    cols=$(${pkgs.coreutils}/bin/stty size 2>/dev/null </dev/tty | ${pkgs.coreutils}/bin/cut -d " " -f 2)
    if [ -n "$cols" ] && [ "$cols" -lt 90 ]; then
      args+=(--logo-position top)
    fi
    for dir in ''${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR/${id}/theme"} /run/${id}/theme; do
      [ -r "$dir/tokens.json" ] || continue
      if read -r name variant < <(${lib.getExe pkgs.jq} -er \
        '[.theme, .variant] | join(" ")' "$dir/tokens.json" 2>/dev/null); then
        logo=${logos}/$name-$variant.png
        [ -f "$logo" ] && args+=(--logo "$logo")
      fi
      break
    done
    exec ${real} "''${args[@]}" "$@"
  '';

  rule = title: {
    type = "custom";
    key = title;
    keyColor = "cyan";
    format = " ";
  };
  entry = type: key: keyColor: extra: { inherit type key keyColor; } // extra;
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
      # In cells, which are about 2.25 times as tall as wide: this keeps the owl square
      width = 36;
      height = 16;
      padding = {
        top = 0;
        right = 2;
      };
    };
    display.separator = ": ";
    modules = [
      (rule "───────────── Hardware ─────────────")
      (entry "host" "󰌢 Machine" "yellow" { })
      (entry "cpu" "󰻠 CPU" "yellow" { })
      (entry "gpu" "󰢮 GPU" "yellow" { })
      (entry "memory" "󰍛 RAM" "yellow" { })
      (entry "disk" "󰋊 Disk /" "red" { folders = "/"; })
      (entry "disk" "󰋊 Disk /boot" "red" { folders = "/boot"; })
      "break"
      (rule "───────────── Software ─────────────")
      (entry "os" "󱄅 OS" "blue" { format = "{pretty-name} {arch}"; })
      (entry "kernel" "󰌽 Kernel" "blue" { })
      (entry "packages" "󰏗 Packages" "green" { })
      (entry "wm" "󰍹 WM" "green" { })
      (entry "shell" "󰆍 Shell" "green" { })
      (entry "terminal" "󰞷 Terminal" "green" { })
      "break"
      (rule "─────────── Uptime / Age ───────────")
      (entry "command" "󰃭 OS Age" "magenta" {
        # Birth time of /, the day of the installation
        text = "birth_install=$(stat -c %W /); current=$(date +%s); echo $(( (current - birth_install) / 86400 )) days";
      })
      (entry "uptime" "󰅐 Uptime" "magenta" { })
    ];
  };
}
