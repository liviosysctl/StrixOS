# fastfetch with the owl of the distro, for every user (/etc/xdg/fastfetch/config.jsonc).
# The logo is the full owl as an image: white eyes, pupils in the accent colour of the god.
# Ghostty shows it through the kitty image protocol. Next to it three framed sections,
# Software, Hardware and Status, with the values as "Label :: value".
{ lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  owl = "/etc/xdg/${branding.id}/fastfetch/owl.png";

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
      format = "{#bright_black}┌${line left} {#red}${title}{#bright_black} ${line (rest - left)}┐";
    };
  frameBottom = {
    type = "custom";
    format = "{#bright_black}└${line (width - 2)}┘";
  };
  # Keys padded by hand, so the :: stand in one column
  pad = name: "  " + name + lib.concatStrings (lib.replicate (9 - lib.stringLength name) " ");
  entry = type: name: extra: { inherit type; key = pad name; } // extra;
in
{
  environment.systemPackages = [ pkgs.fastfetch ];

  environment.etc."xdg/${branding.id}/fastfetch/owl.png".source = ../shell/fastfetch/owl.png;

  environment.etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
    logo = {
      type = "auto";
      source = owl;
      width = 36;
      height = 18;
      padding.right = 4;
    };
    display = {
      separator = " :: ";
      color = {
        keys = "default";
        title = "red";
        separator = "bright_black";
        output = "default";
      };
      # One accent: bars in red, numbers only turn red when nearly full
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
          elapsed = "red";
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
        format = "{#red}{user-name}{#}{#bright_black} @ {#}{host-name}";
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
