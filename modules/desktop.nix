# The desktop (12-desktop in the plan): Hyprland as a systemd session through UWSM, the login of
# Strix (shell/greeter, Quickshell in cage under greetd; tuigreet if chosen), PipeWire, and the
# apps of the cheat sheet.
#
# Hyprland reads the configuration of Strix from /etc/xdg/strix/hypr (HYPRLAND_CONFIG):
# shell/hypr/hyprland.lua, machine.lua from this module, bindings.lua made by strix-search from
# shell/menu.toml, and theme.lua, which reads the colors of the session's theme.
#
# The session has its own theme on top of the machine's (Q14): the user service
# <id>-theme-session (`<id>-theme session`) shows another god every 10 minutes unless kept,
# writes tokens.json, hyprland.lua, ghostty and btop.theme into $XDG_RUNTIME_DIR/<id>/theme and
# reloads Hyprland, Ghostty and btop. Choosing a theme by hand in the picker sets the machine's
# theme through pkexec; polkit lets the active local session do that, and only that, without a
# password.
#
# The shell is Quickshell with shell/qml, installed as /etc/xdg/quickshell/<id> and started by
# the user service <id>-shell (`qs -c <id>`); it imports the QML module of StrixUI. hypridle
# locks after five minutes and before sleep, through the shell's lock screen.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;

  # Neovim is the editor: text opened from Files or elsewhere goes to it in a Ghostty window
  neovimWindow = pkgs.makeDesktopItem {
    name = "${id}-neovim";
    desktopName = "Neovim";
    comment = "Edit text in Neovim";
    exec = "ghostty -e nvim %F";
    icon = "nvim";
    categories = [ "Utility" "TextEditor" ];
    mimeTypes = [ "text/plain" "text/markdown" "text/x-nix" "application/json" "application/toml" "application/x-shellscript" ];
    # Only for opening files; app lists and Search show Neovim's own entry
    noDisplay = true;
  };

  # Files › Scripts › Open in Ghostty: a terminal in the folder shown, or in the folder of the
  # first selected item. Nautilus gives the selection as paths, the folder only as a URI
  openInGhostty = pkgs.writeShellApplication {
    name = "open-in-ghostty";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused ];
    text = ''
      dir=$(printf '%s\n' "''${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS:-}" | head -n 1)
      if [ -n "$dir" ]; then
        [ -d "$dir" ] || dir=$(dirname "$dir")
      else
        uri=''${NAUTILUS_SCRIPT_CURRENT_URI:-}
        dir=$(printf '%b' "$(printf '%s' "''${uri#file://}" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")
      fi
      # Not a local folder (a phone, a network share): the home folder
      [ -d "$dir" ] || dir=$HOME
      exec ghostty --working-directory="$dir"
    '';
  };

  # The browser: Zen, the only one installed (flake input zen-browser, not in nixpkgs)
  zen = distroFlake.inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
  xkb = config.services.xserver.xkb;
  runtimeDir = "/run/${id}/theme";
  luaString = s: builtins.toJSON s;
  themeCommand = lib.getExe config.${id}.theme.package;

  # How often the session changes its theme: theme-cycle of the design system (600s)
  tokens = lib.importJSON "${distroFlake.inputs.strixui}/design-system/tokens.json";
  tokenCycle =
    (lib.findFirst (t: t.name == "theme-cycle") { value = "600s"; } tokens.duration.tokens).value;
  cyclePeriod = cfg.themeCycle;

  # theme.lua: the session's colors, else the machine's (before the session service started)
  themeLua = pkgs.writeText "theme.lua" ''
    -- The colors of the current theme (modules/desktop.nix): the session's theme, which
    -- changes every ${cyclePeriod} (${id}-theme session), else the machine's.
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    local files = { "${runtimeDir}/hyprland.lua" }
    if runtime then
        table.insert(files, 1, runtime .. "/${id}/theme/hyprland.lua")
    end
    for _, file in ipairs(files) do
        local handle = io.open(file, "r")
        if handle then
            handle:close()
            dofile(file)
            return
        end
    end
  '';

  # After every change of the session's theme: Hyprland and every Ghostty window read their
  # colors again
  sessionHook = pkgs.writeShellScript "${id}-theme-reload" ''
    # Hyprland's socket may not answer in time while it is busy (software rendering): try for
    # up to two minutes; this runs beside the session service and holds nothing up
    for try in 1 2 3 4 5 6 7 8 9 10; do
      ${config.programs.hyprland.package}/bin/hyprctl reload && break
      echo "hyprctl reload failed ($try)"
      sleep 3
    done
    ${pkgs.procps}/bin/pkill -USR2 -x ghostty || true
    ${pkgs.procps}/bin/pkill -USR2 -x btop || true
  '';

  machineLua = pkgs.writeText "machine.lua" (
    ''
      -- This machine, from machine.nix (modules/desktop.nix).
      hl.config({
          input = {
              kb_layout = ${luaString xkb.layout},
              kb_variant = ${luaString xkb.variant},
              kb_options = ${luaString xkb.options},
          },
      })
    ''
    + lib.optionalString (cfg.extraConfig != "") ''

      -- strix.desktop.extraConfig
      ${cfg.extraConfig}
    ''
  );

  search = config.${id}.search.package;

  # Everything Hyprland reads, in one folder: `require` looks next to hyprland.lua
  hyprConfig = pkgs.runCommand "${id}-hyprland-config" { } ''
    mkdir $out
    cp ${../shell/hypr/hyprland.lua} $out/hyprland.lua
    cp ${machineLua} $out/machine.lua
    MENU_FILE=${search}/share/${id}-search/menu.toml SEARCH_ID=${id} \
      ${lib.getExe search} bindings > $out/bindings.lua
    cp ${themeLua} $out/theme.lua
  '';

  ui = config.${id}.ui.package;
  sessionCommand = "uwsm start -e -D Hyprland hyprland.desktop";

  # Screenshots, a recording, the colour picker: <id>-capture region|window|screen|record|colour
  captureCommand = pkgs.writeShellApplication {
    name = "${id}-capture";
    runtimeInputs = with pkgs; [
      grim
      slurp
      wl-clipboard
      jq
      libnotify
      wf-recorder
      hyprpicker
      procps
      coreutils
      config.programs.hyprland.package
    ];
    text = builtins.readFile ../shell/bin/capture.sh;
  };

  # The system monitor of the bar's load figures: <id>-monitor (btop in Ghostty)
  monitorCommand = pkgs.writeShellApplication {
    name = "${id}-monitor";
    runtimeInputs = with pkgs; [
      btop
      ghostty
      jq
      coreutils
      gnused
      uwsm
      config.programs.hyprland.package
    ];
    runtimeEnv.ID = id;
    text = builtins.readFile ../shell/bin/monitor.sh;
  };

  # Settings at a page and a row, for Search and people: <id>-settings [PAGE [ROW]]
  settingsCommand = pkgs.writeShellScriptBin "${id}-settings" ''
    exec ${lib.getExe' pkgs.quickshell "qs"} -c ${id} ipc call settings open "''${1:-themes}" "''${2:-}"
  '';
  greeterState = "/var/lib/${id}-greeter";

  # The login: Quickshell with shell/greeter in cage, as the user greeter
  greeterCommand = pkgs.writeShellScript "${id}-greeter" ''
    export QML_IMPORT_PATH=${ui}/share/${id}-ui/qml
    export XDG_CONFIG_DIRS=/etc/xdg
    export XDG_CACHE_HOME=${greeterState}/cache XDG_STATE_HOME=${greeterState}/state
    export GREETER_STATE=${greeterState} GREETER_SESSION=${lib.escapeShellArg sessionCommand}
    export STRIX_LOGOS=${config.${id}.theme.logos}
    export XKB_DEFAULT_LAYOUT=${lib.escapeShellArg xkb.layout} XKB_DEFAULT_VARIANT=${lib.escapeShellArg xkb.variant}
    export XKB_DEFAULT_OPTIONS=${lib.escapeShellArg xkb.options}
    export XCURSOR_THEME=Adwaita XCURSOR_SIZE=24
    # A machine without usable 3D (an old GPU, a VM): wlroots refuses Mesa's software renderer
    # unless allowed; with a working GPU this changes nothing
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    # Early in the boot the keyboard may not be there yet: start anyway, it comes by hotplug
    export WLR_LIBINPUT_NO_DEVICES=1
    # greetd keeps no output of the greeter: to the journal, as ${id}-greeter
    exec ${pkgs.systemd}/bin/systemd-cat -t ${id}-greeter -- \
      ${lib.getExe pkgs.cage} -s -d -- ${lib.getExe' pkgs.quickshell "qs"} -c ${id}-greeter
  '';
  qmlPath = "/run/current-system/sw/share/${id}-ui/qml";
  # PATH for user services that start programs: the user's profiles, the setuid wrappers, the system
  sessionPath = lib.concatStringsSep ":" [
    "%h/.nix-profile/bin"
    "/etc/profiles/per-user/%u/bin"
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
  ];

  hypridleConfig = pkgs.writeText "hypridle.conf" ''
    # Idle and sleep (modules/desktop.nix): lock through the shell of ${branding.name}
    general {
        lock_cmd = qs -c ${id} ipc call lock lock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
    }
    listener {
        timeout = 300
        on-timeout = loginctl lock-session
    }
    listener {
        timeout = 330
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
    }
  '';

  # Copied once into a new user's ~/.config/ghostty/config, then theirs to change
  ghosttyUser = pkgs.writeText "ghostty-config" ''
    # Made by ${branding.name} for you; change it as you like.
    # The look of ${branding.name} first, then the colors of the current theme, which follow every
    # switch (strix-theme is a link to the session's colors). Remove a line to keep your own.
    config-file = ?/etc/xdg/${id}/ghostty/defaults
    config-file = ?${id}-theme
  '';

  ghosttyDefaults = pkgs.writeText "ghostty-defaults" ''
    # The look of ${branding.name} (modules/desktop.nix)
    font-family = GeistMono Nerd Font Mono
    font-style = SemiBold
    font-style-bold = ExtraBold
    font-size = 13
    window-padding-x = 12
    window-padding-y = 8
    window-decoration = none
    gtk-titlebar = false
    confirm-close-surface = false
    cursor-style = bar
  '';
in
{
  # Starship in every terminal, with the bars for user, git and path
  imports = [ ./prompt.nix ];

  options.${id}.desktop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The desktop: Hyprland, the login, sound and the apps of the cheat sheet.";
    };

    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
      description = ''
        The live session of the ISO (iso/live.nix): logged in at once as nixos, never locked,
        without the apps of an installed machine.
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        hl.config({ general = { gaps_out = 4 } })
        hl.bind("SUPER + B", hl.dsp.exec_cmd("uwsm app -- zen-beta"))
      '';
      description = ''
        Own Hyprland settings in Lua, read after the ones of ${branding.name}. Each user can also
        keep their own in ~/.config/${id}/hyprland.lua.
      '';
    };

    themeCycle = lib.mkOption {
      type = lib.types.strMatching "[0-9]+s";
      default = tokenCycle;
      defaultText = lib.literalExpression ''"600s" (theme-cycle of StrixUI)'';
      description = "How often the session moves on to another god, unless the theme is kept.";
    };

    greeter = lib.mkOption {
      type = lib.types.enum [ "strix" "tuigreet" ];
      default = "strix";
      description = "The login: the own one in Quickshell, or tuigreet in the console.";
    };

    lid = lib.mkOption {
      type = lib.types.enum [ "suspend" "hibernate" "lock" "ignore" ];
      default = "suspend";
      description = ''
        What closing the lid does on battery and on power: suspend (the default), hibernate
        (needs a swap file large enough, strix.storage.hibernation), lock the screen, or nothing.
        With an external screen connected nothing happens either way. Settings › Power shows it.
      '';
    };

    hyprlandConfig = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = hyprConfig;
      description = "The folder Hyprland reads, for tests.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    environment.etc."xdg/${id}/hypr".source = hyprConfig;
    environment.etc."xdg/quickshell/${id}".source = ../shell/qml;
    environment.etc."xdg/${id}/hypridle.conf".source = hypridleConfig;
    environment.etc."xdg/${id}/ghostty/defaults".source = ghosttyDefaults;
    environment.etc."xdg/${id}/ghostty/user".source = ghosttyUser;
    environment.sessionVariables = {
      HYPRLAND_CONFIG = "/etc/xdg/${id}/hypr/hyprland.lua";
      XCURSOR_THEME = "Adwaita";
      XCURSOR_SIZE = "24";
      NIXOS_OZONE_WL = "1";
    };

    # The login. Both start the same UWSM session as the session file of Hyprland.
    services.greetd = {
      enable = true;
      # The live session starts without asking; logging out leads to the normal login
      settings.initial_session = lib.mkIf cfg.live {
        user = "nixos";
        command = sessionCommand;
      };
      settings.default_session = {
        user = "greeter";
        command =
          if cfg.greeter == "strix" then
            "${greeterCommand}"
          else
            lib.concatStringsSep " " [
              (lib.getExe pkgs.tuigreet)
              "--time"
              "--remember"
              "--asterisks"
              "--greeting ${lib.escapeShellArg branding.name}"
              "--cmd ${lib.escapeShellArg sessionCommand}"
            ];
      };
    };
    # The login with the owl of the shell (Owl.qml) beside it
    environment.etc."xdg/quickshell/${id}-greeter".source = pkgs.runCommand "${id}-greeter" { } ''
      mkdir $out
      cp ${../shell/greeter/shell.qml} $out/shell.qml
      cp ${../shell/qml/Owl.qml} $out/Owl.qml
    '';
    systemd.tmpfiles.rules = lib.mkIf (cfg.greeter == "strix") [
      "d ${greeterState} 0750 greeter greeter -"
    ];

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    security.rtkit.enable = true;
    # The battery in the bar, the power profiles and Bluetooth of Settings
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
    };

    # Closing the lid (Settings › Power shows it); locking comes from hypridle before sleep
    services.logind.settings.Login = {
      HandleLidSwitch = cfg.lid;
      HandleLidSwitchExternalPower = cfg.lid;
      HandleLidSwitchDocked = "ignore";
    };
    environment.etc."xdg/${id}/lid".text = cfg.lid + "\n";
    security.polkit.enable = true;

    programs.dconf = {
      enable = true;
      # Every god is dark: GTK and libadwaita apps follow. adw-gtk3 makes GTK 3 apps look like
      # libadwaita and read the same named colors, so both take the god's colors from gtk.css
      profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-theme = "adw-gtk3-dark";
            cursor-theme = "Adwaita";
            monospace-font-name = "JetBrains Mono 11";
          };
        }
      ];
    };
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # Files (Nautilus, Super E): phones, network shares and the trash (gvfs), other drives
    # (udisks2, mounted without a password by the admins, see the polkit rule below) and
    # thumbnails of pictures and videos. Its colors come from the theme like every GTK app's
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.tumbler.enable = !cfg.live;
    environment.pathsToLink = lib.mkIf (!cfg.live) [ "/share/thumbnailers" ];
    environment.etc."xdg/${id}/nautilus/open-in-ghostty" = lib.mkIf (!cfg.live) {
      source = lib.getExe openInGhostty;
    };

    # Noto for text in every script; Geist Mono with the Nerd Font icons for the terminal and its
    # prompt
    fonts.packages = [ pkgs.noto-fonts pkgs.nerd-fonts.geist-mono ];

    # The search service behind Search and the cheat sheet
    ${id}.search.enable = true;

    # The password of the lock screen
    security.pam.services."${id}-lock" = { };

    # Links, web pages and PDFs open in Zen, text in Neovim; the live session of the ISO has
    # neither
    xdg.mime.defaultApplications = lib.mkIf (!cfg.live) (
      lib.genAttrs [
        "text/html"
        "application/xhtml+xml"
        "application/pdf"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ] (_: "zen-beta.desktop")
      // lib.genAttrs [
        "text/plain"
        "text/markdown"
        "text/x-nix"
        "application/json"
        "application/toml"
        "application/x-shellscript"
      ] (_: "${id}-neovim.desktop")
    );
    environment.sessionVariables.BROWSER = lib.mkIf (!cfg.live) "zen-beta";

    environment.systemPackages = with pkgs; [
      settingsCommand
      captureCommand
      monitorCommand
      btop
      libnotify
      quickshell
      ghostty
    ]
    ++ lib.optionals (!cfg.live) [
      zen
      cliphist
      nautilus
      neovimWindow
      amberol
    ]
    ++ [
      adwaita-icon-theme
      adw-gtk3
      wl-clipboard
      grim
      slurp
      hyprpicker
      brightnessctl
      playerctl
      hypridle
    ];

    systemd.user.services."${id}-shell" = {
      description = "The shell of ${branding.name}: wallpaper, bar, lock screen, search, notifications";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      environment = {
        # Programs started from here (Search, the bar, the keys) need the session's commands on
        # PATH: NixOS gives a user service only a handful of tools
        PATH = lib.mkForce sessionPath;
        QML_IMPORT_PATH = qmlPath;
        # The owl in the colors of every theme, for the lock screen and Settings (Owl.qml)
        STRIX_LOGOS = "${config.${id}.theme.logos}";
      };
      # Theme.qml finds the wallpapers next to the module, the path must not be resolved
      restartTriggers = [ ui ../shell/qml ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.quickshell "qs"} -c ${id}";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # The clipboard history behind Super V: text and pictures, kept by cliphist
    systemd.user.services."${id}-clipboard" = lib.mkIf (!cfg.live) {
      description = "Keep a history of the clipboard";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      path = [ pkgs.wl-clipboard pkgs.cliphist ];
      script = ''
        wl-paste --type text --watch cliphist store &
        exec wl-paste --type image --watch cliphist store
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # Nothing to lock in the live session: the user has no password
    systemd.user.services.hypridle = lib.mkIf (!cfg.live) {
      description = "Lock and dim when idle";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      path = [ pkgs.quickshell config.programs.hyprland.package pkgs.systemd ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.hypridle} -c /etc/xdg/${id}/hypridle.conf";
        Restart = "on-failure";
      };
    };

    systemd.user.services.hyprpolkitagent = {
      description = "Asks for the password when an app needs more rights";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
      };
    };

    # A new user gets the Ghostty config that follows the theme; an existing one stays. The link to
    # the session's colors is made every time. Users without a home of their own are left alone.
    systemd.user.services."${id}-ghostty-config" = {
      description = "Give Ghostty the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        mkdir -p "$HOME/.config/ghostty"
        [ -e "$HOME/.config/ghostty/config" ] || install -m 0644 /etc/xdg/${id}/ghostty/user "$HOME/.config/ghostty/config"
        ln -sfn "$XDG_RUNTIME_DIR/${id}/theme/ghostty" "$HOME/.config/ghostty/${id}-theme"
      '';
    };

    # "Open in Ghostty" among the scripts of Files. The link is made only where the user has no
    # script of that name of their own (or already has the link)
    systemd.user.services."${id}-files-scripts" = lib.mkIf (!cfg.live) {
      description = "Give Files the script that opens Ghostty in a folder";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        target=/etc/xdg/${id}/nautilus/open-in-ghostty
        link="$HOME/.local/share/nautilus/scripts/Open in Ghostty"
        if [ -e "$link" ] || [ -L "$link" ]; then
          [ "$(readlink "$link")" = "$target" ] || echo "$link is the user's own, left alone"
          exit 0
        fi
        mkdir -p "''${link%/*}"
        ln -s "$target" "$link"
      '';
    };

    # GTK 3 and GTK 4 apps take the god's colors from the session's gtk3.css and gtk4.css. The link
    # is made only where the user has no gtk.css of their own (or already has the link); apps read
    # the file when they start, so a running app keeps its colors until it is opened again
    systemd.user.services."${id}-gtk-colors" = {
      description = "Give GTK apps the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        for version in 3 4; do
          target="$XDG_RUNTIME_DIR/${id}/theme/gtk$version.css"
          file="$HOME/.config/gtk-$version.0/gtk.css"
          mkdir -p "''${file%/*}"
          if [ -L "$file" ] && [ "$(readlink "$file")" = "$target" ]; then
            continue
          fi
          if [ -e "$file" ] || [ -L "$file" ]; then
            echo "$file is the user's own, left alone"
            continue
          fi
          ln -s "$target" "$file"
        done
      '';
    };

    # The session's theme (Q14, Q15): its own colors, another god every period unless kept, the
    # socket for the theme picker
    systemd.user.services."${id}-theme-session" = {
      description = "The theme of the session: another god every ${cyclePeriod} unless kept";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      before = [ "${id}-shell.service" ];
      environment = {
        SESSION_DIR = "%t/${id}/theme";
        SESSION_STATE = "%S/${id}/theme-session.json";
        SESSION_SOCKET = "%t/${id}/theme.sock";
        CYCLE_PERIOD = cyclePeriod;
        SESSION_HOOK = "${sessionHook}";
        PKEXEC = "/run/wrappers/bin/pkexec";
        THEME_COMMAND = themeCommand;
      };
      serviceConfig = {
        Type = "notify";
        ExecStart = "${themeCommand} session";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # The theme picker sets the machine's theme through pkexec: the active local session may run
    # exactly `<id>-theme set <theme>` without a password. Every other pkexec still asks.
    # nixpkgs no longer installs the setuid pkexec by itself.
    security.polkit.enablePkexecWrapper = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" &&
            action.lookup("program") == "${themeCommand}" &&
            /^\S+ set [a-z0-9:-]+$/.test(action.lookup("command_line") || "") &&
            subject.local && subject.active) {
          return polkit.Result.YES;
        }
      });

      // Files mounts other drives for the admins without a password, as on the desktop of most
      // distributions; everyone else is asked
      polkit.addRule(function (action, subject) {
        if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
             action.id == "org.freedesktop.udisks2.filesystem-mount-system") &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
