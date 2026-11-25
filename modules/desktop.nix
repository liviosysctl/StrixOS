# The desktop (12-desktop in the plan): Hyprland as a systemd session through UWSM, the login of
# Strix (shell/greeter, Quickshell in cage under greetd; tuigreet if chosen), PipeWire, and a
# few apps. The proof of concept keeps it simple: one theme, no clipboard history; the cheat sheet
# (Super K) and Settings are those of main.
#
# Hyprland reads the configuration of Strix from /etc/xdg/strix/hypr (HYPRLAND_CONFIG):
# shell/hypr/hyprland.lua, machine.lua from this module, bindings.lua made by strix-search from
# shell/menu.toml, and theme.lua, which reads the colors of the session's theme.
#
# The user service <id>-theme-session (`<id>-theme session`) writes the session's tokens.json,
# hyprland.lua, ghostty and btop.theme into $XDG_RUNTIME_DIR/<id>/theme. The proof of concept has
# a single theme (lib/builtin-themes.nix), so it never moves on to another one.
#
# The shell is Quickshell with shell/qml, installed as /etc/xdg/quickshell/<id> and started by
# the user service <id>-shell (`qs -c <id>`); it imports the QML module of StrixUI. hypridle
# dims, locks and sleeps with the times of Settings › Power (<id>-idle, packages/desk), and locks
# before sleep, through the shell's lock screen.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;

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
  # It reads userChrome.css of the profile, where the colors of the theme arrive (see the
  # <id>-zen-colors service); Zen leaves that switched off by itself.
  zen = distroFlake.inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraPolicies.Preferences."toolkit.legacyUserProfileCustomizations.stylesheets" = {
      Value = true;
      Status = "default";
    };
  };
  xkb = config.services.xserver.xkb;
  runtimeDir = "/run/${id}/theme";
  luaString = s: builtins.toJSON s;
  themeCommand = lib.getExe config.${id}.theme.package;

  # How often the session changes its theme: theme-cycle of the design system (600s)
  tokens = lib.importJSON "${distroFlake.inputs.strixui}/design-system/tokens.json";
  tokenCycle =
    (lib.findFirst (t: t.name == "theme-cycle") { value = "600s"; } tokens.duration.tokens).value;
  cyclePeriod = cfg.themeCycle;

  # The settings a new user's Zed starts with: the theme of the system, the fonts of StrixUI,
  # no telemetry, no updates of its own (Nix updates it)
  zedSettings = pkgs.writeText "zed-settings.json" (builtins.toJSON {
    theme = branding.name;
    ui_font_family = "Hanken Grotesk";
    buffer_font_family = "IBM Plex Mono";
    telemetry = { diagnostics = false; metrics = false; };
    auto_update = false;
  });

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

  # The commands of the desktop (packages/desk), as on main
  desk = pkgs.callPackage ../packages/desk { };

  # Screenshots, a recording, the colour picker: <id>-capture region|window|screen|record|colour
  captureCommand = desk.command "capture" (
    with pkgs;
    [
      grim
      slurp
      wl-clipboard
      libnotify
      wf-recorder
      hyprpicker
      procps
      config.programs.hyprland.package
    ]
  );

  # The system monitor of the bar's load figures: <id>-monitor (btop in Ghostty)
  monitorCommand = desk.command "monitor" (
    with pkgs;
    [
      btop
      ghostty
      uwsm
      config.programs.hyprland.package
    ]
  );

  # What happens when nobody is at the machine: <id>-idle, which runs hypridle with the times of
  # ~/.config/<id>/idle.json (Settings › Power), apart for power and battery, and keeps awake
  idleCommand = desk.command "idle" (
    with pkgs;
    [
      hypridle
      brightnessctl
      systemd
      quickshell
      config.programs.hyprland.package
    ]
  );

  # The night light: warmer colors in the evening (hyprsunset, from 20:00 to 7:00), and by hand
  # until the next of those hours: <id>-nightlight on|off|toggle|state
  nightTemperature = 4500;
  nightlightCommand = pkgs.writeShellApplication {
    name = "${id}-nightlight";
    runtimeInputs = [
      config.programs.hyprland.package
      pkgs.coreutils
    ];
    text = ''
      state() {
        now=$(hyprctl hyprsunset temperature 2>/dev/null | tr -dc '0-9' || true)
        if [ -n "$now" ] && [ "$now" -lt 6000 ]; then echo on; else echo off; fi
      }
      case "''${1:-state}" in
        state) state ;;
        on) hyprctl hyprsunset temperature ${toString nightTemperature} >/dev/null ;;
        off) hyprctl hyprsunset identity >/dev/null ;;
        toggle) if [ "$(state)" = on ]; then "$0" off; else "$0" on; fi ;;
        *) echo "Usage: $(basename "$0") on|off|toggle|state" >&2; exit 64 ;;
      esac
    '';
  };

  # Settings at a page and a row, for Search and people: <id>-settings [PAGE [ROW]]
  settingsCommand = pkgs.writeShellScriptBin "${id}-settings" ''
    exec ${lib.getExe' pkgs.quickshell "qs"} -c ${id} ipc call settings open "''${1:-home}" "''${2:-}"
  '';
  # Settings among the apps, like any other
  settingsEntry = pkgs.makeDesktopItem {
    name = "${id}-settings";
    desktopName = "Settings";
    comment = "Network, sound, display, input, power, hotkeys, versions";
    exec = "${id}-settings";
    icon = "preferences-system";
    categories = [ "Settings" ];
  };
  greeterState = "/var/lib/${id}-greeter";

  # The login: Quickshell with shell/greeter in cage, as the user greeter
  greeterCommand = pkgs.writeShellScript "${id}-greeter" ''
    export QML_IMPORT_PATH=${ui}/share/${id}-ui/qml
    export XDG_CONFIG_DIRS=/etc/xdg
    export XDG_CACHE_HOME=${greeterState}/cache XDG_STATE_HOME=${greeterState}/state
    export GREETER_STATE=${greeterState} GREETER_SESSION=${lib.escapeShellArg sessionCommand}
    export XKB_DEFAULT_LAYOUT=${lib.escapeShellArg xkb.layout} XKB_DEFAULT_VARIANT=${lib.escapeShellArg xkb.variant}
    export XKB_DEFAULT_OPTIONS=${lib.escapeShellArg xkb.options}
    export XCURSOR_THEME=Adwaita XCURSOR_SIZE=24
    # cage does not scale: a laptop's own Full HD screen gets the 125 % of the desktop
    # (shell/hypr/hyprland.lua), so the login is as large as what follows it
    for modes in /sys/class/drm/card*-eDP-*/modes; do
      [ -r "$modes" ] || continue
      case "$(${pkgs.coreutils}/bin/head -n 1 "$modes")" in
        1920x1080 | 1920x1200) export QT_SCALE_FACTOR=1.25 ;;
      esac
    done
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
    font-family = BlexMono Nerd Font Mono
    font-style = SemiBold
    font-style-bold = Bold
    font-size = 13
    # Smoked glass: the compositor blurs what lies behind the terminal
    background-opacity = 0.72
    window-padding-x = 12
    window-padding-y = 8
    window-decoration = none
    gtk-titlebar = false
    confirm-close-surface = false
    cursor-style = bar
  '';
in
{
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
    environment.etc."xdg/quickshell/${id}-greeter".source = ../shell/greeter;
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
            monospace-font-name = "IBM Plex Mono 11";
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

    # Noto for text in every script; IBM Plex Mono with the Nerd Font icons (BlexMono) for the
    # terminal
    fonts.packages = [ pkgs.noto-fonts pkgs.nerd-fonts.blex-mono ];

    # The search service behind Search and the cheat sheet
    ${id}.search.enable = true;

    # The password of the lock screen
    security.pam.services."${id}-lock" = { };

    # Links, web pages and PDFs open in Zen, text in Zed; the live session of the ISO has neither
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
      ] (_: "dev.zed.Zed.desktop")
    );
    environment.sessionVariables.BROWSER = lib.mkIf (!cfg.live) "zen-beta";

    # Video is decoded by the graphics card where it can be. Mesa brings the drivers for that
    # for most cards; Intel's newer ones need this one.
    hardware.graphics.extraPackages = lib.mkIf (!cfg.live) [ pkgs.intel-media-driver ];

    environment.systemPackages = with pkgs; [
      settingsCommand
      settingsEntry
      captureCommand
      monitorCommand
      btop
      libnotify
      quickshell
      ghostty
    ]
    ++ lib.optionals (!cfg.live) [
      zen
      nautilus
      # The editor of the proof of concept: plain to use, in the theme's colors
      zed-editor
      jq
      amberol
      idleCommand
      nightlightCommand
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
      environment.QML_IMPORT_PATH = qmlPath;
      # Programs started from here (Search, the bar, the keys) need the session's commands on
      # PATH: NixOS gives a user service only a handful of tools
      environment.PATH = lib.mkForce sessionPath;
      # Theme.qml finds the wallpapers next to the module, the path must not be resolved
      restartTriggers = [ ui ../shell/qml ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.quickshell "qs"} -c ${id}";
        Restart = "on-failure";
        RestartSec = 1;
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
        ExecStart = "${lib.getExe idleCommand} run";
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

    # The night light: hyprsunset with the hours of /etc/xdg/hypr/hyprsunset.conf, or the user's
    # own ~/.config/hypr/hyprsunset.conf
    environment.etc."xdg/hypr/hyprsunset.conf" = lib.mkIf (!cfg.live) {
      text = ''
        profile {
            time = 7:00
            identity = true
        }

        profile {
            time = 20:00
            temperature = ${toString nightTemperature}
        }
      '';
    };
    systemd.user.services."${id}-nightlight" = lib.mkIf (!cfg.live) {
      description = "Warmer colors in the evening";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      script = ''
        if [ ! -e "''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf" ]; then
          export XDG_CONFIG_HOME=/etc/xdg
        fi
        exec ${lib.getExe pkgs.hyprsunset}
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # The first login shows the cheat sheet once: the keys are all one needs to know
    systemd.user.services."${id}-welcome" = lib.mkIf (!cfg.live) {
      description = "Show the cheat sheet at the first login";
      partOf = [ "graphical-session.target" ];
      after = [ "${id}-shell.service" ];
      wantedBy = [ "graphical-session.target" ];
      path = [ pkgs.quickshell pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        seen="''${XDG_STATE_HOME:-$HOME/.local/state}/${id}/welcomed"
        [ ! -e "$seen" ] || exit 0
        for _ in $(seq 1 30); do
          if [ "$(qs -c ${id} ipc call cheatsheet isOpen 2>/dev/null)" = false ]; then
            sleep 3
            qs -c ${id} ipc call cheatsheet toggle
            mkdir -p "''${seen%/*}"
            touch "$seen"
            exit 0
          fi
          sleep 2
        done
      '';
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

    # Zed takes the colors of the session's theme: its theme file is written from tokens.json
    # at login and again whenever the god changes (the path unit). A new user also gets
    # settings that choose it; an existing settings.json stays as it is.
    systemd.user.services."${id}-zed-theme" = lib.mkIf (!cfg.live) {
      description = "Give Zed the colors of the session's theme";
      wantedBy = [ "default.target" ];
      path = [ pkgs.jq pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        tokens="$XDG_RUNTIME_DIR/${id}/theme/tokens.json"
        [ -r "$tokens" ] || tokens="${runtimeDir}/tokens.json"
        [ -r "$tokens" ] || exit 0
        dir="$HOME/.config/zed"
        mkdir -p "$dir/themes"
        jq --arg name ${lib.escapeShellArg branding.name} -f ${../shell/zed/theme.jq} "$tokens" >"$dir/themes/${id}.json.new"
        mv "$dir/themes/${id}.json.new" "$dir/themes/${id}.json"
        [ -e "$dir/settings.json" ] || install -m 0644 ${zedSettings} "$dir/settings.json"
      '';
    };
    systemd.user.paths."${id}-zed-theme" = lib.mkIf (!cfg.live) {
      description = "Follow the session's theme in Zed";
      wantedBy = [ "default.target" ];
      pathConfig.PathChanged = "%t/${id}/theme/tokens.json";
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

    # Zen takes the god's colors from the session's zen-userChrome.css and zen-userContent.css,
    # linked into chrome/ of every profile, and its settings from zen-user.js, linked as user.js.
    # As with GTK, a file of the user's own stays. Zen makes its profile at its first start, so
    # the path unit links it then; Zen reads the files when it starts, so they show from the
    # next start on.
    systemd.user.services."${id}-zen-colors" = lib.mkIf (!cfg.live) {
      description = "Give Zen the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.gnused
      ];
      script = ''
        [ -w "$HOME" ] || exit 0
        for ini in "$HOME/.config/zen/profiles.ini" "$HOME/.zen/profiles.ini"; do
          [ -r "$ini" ] || continue
          sed -n 's/^Path=//p' "$ini" | while IFS= read -r path; do
            case "$path" in
              /*) profile=$path ;;
              *) profile=''${ini%/*}/$path ;;
            esac
            [ -d "$profile" ] || continue
            mkdir -p "$profile/chrome"
            for name in chrome/userChrome.css chrome/userContent.css user.js; do
              target="$XDG_RUNTIME_DIR/${id}/theme/zen-''${name##*/}"
              file="$profile/$name"
              if [ -L "$file" ] && [ "$(readlink "$file")" = "$target" ]; then
                continue
              fi
              if [ -e "$file" ] || [ -L "$file" ]; then
                echo "$file is the user's own, left alone"
                continue
              fi
              ln -s "$target" "$file"
            done
          done
        done
      '';
    };
    systemd.user.paths."${id}-zen-colors" = lib.mkIf (!cfg.live) {
      description = "Link the colors into a new Zen profile";
      wantedBy = [ "default.target" ];
      pathConfig.PathChanged = [
        "%h/.config/zen/profiles.ini"
        "%h/.zen/profiles.ini"
      ];
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
        # The prompt's configuration, written again in the colors of the god (modules/prompt.nix)
        PROMPT_BASE = "${../shell/starship.toml}";
        # The shape and the settings of Zen: the file of ${branding.name}, then the user's own
        BROWSER_BASE = "${../shell/browser.toml}";
        BROWSER_USER = "%E/${id}/browser.toml";
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
