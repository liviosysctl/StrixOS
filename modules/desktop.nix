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
# writes tokens.json, hyprland.lua and ghostty into $XDG_RUNTIME_DIR/<id>/theme and reloads
# Hyprland and Ghostty. Choosing a theme by hand in the picker sets the machine's theme through
# pkexec; polkit lets the active local session do that, and only that, without a password.
#
# The shell is Quickshell with shell/qml, installed as /etc/xdg/quickshell/<id> and started by
# the user service <id>-shell (`qs -c <id>`); it imports the QML module of StrixUI. hypridle
# locks after five minutes and before sleep, through the shell's lock screen.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;
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
    font-family = JetBrains Mono
    font-size = 11
    window-padding-x = 12
    window-padding-y = 8
    window-decoration = none
    gtk-titlebar = false
    confirm-close-surface = false
    cursor-style = block
    shell-integration-features = no-cursor
  '';
in
{
  options.${id}.desktop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The desktop: Hyprland, the login, sound and the apps of the cheat sheet.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        hl.config({ general = { gaps_out = 4 } })
        hl.bind("SUPER + B", hl.dsp.exec_cmd("uwsm app -- firefox"))
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
    security.polkit.enable = true;

    programs.firefox.enable = true;
    programs.dconf = {
      enable = true;
      # Every god is dark: GTK and libadwaita apps follow
      profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-theme = "Adwaita-dark";
            cursor-theme = "Adwaita";
            monospace-font-name = "JetBrains Mono 11";
          };
        }
      ];
    };
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    services.gvfs.enable = true;

    fonts.packages = [ pkgs.noto-fonts ];

    # The search service behind Search and the cheat sheet
    ${id}.search.enable = true;

    # The password of the lock screen
    security.pam.services."${id}-lock" = { };

    environment.systemPackages = with pkgs; [
      settingsCommand
      quickshell
      ghostty
      nautilus
      gnome-text-editor
      amberol
      adwaita-icon-theme
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
      # Theme.qml finds the wallpapers next to the module, the path must not be resolved
      restartTriggers = [ ui ../shell/qml ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.quickshell "qs"} -c ${id}";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    systemd.user.services.hypridle = {
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
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" &&
            action.lookup("program") == "${themeCommand}" &&
            /^\S+ set [a-z0-9:-]+$/.test(action.lookup("command_line") || "") &&
            subject.local && subject.active) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
