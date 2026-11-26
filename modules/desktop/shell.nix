# The shell: Quickshell with shell/qml, installed as /etc/xdg/quickshell/<id> and started by the
# user service <id>-shell (`qs -c <id>`); it imports the QML module of StrixUI. With it come the
# commands it starts (settings, capture, monitor), the clipboard history and the cheat sheet at
# the first login.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;

  ui = config.${id}.ui.package;

  # The commands of the desktop (packages/desk)
  desk = pkgs.callPackage ../../packages/desk { };

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
      # Drawing on a screenshot, and reading the words in one (the languages of the installer)
      satty
      (tesseract.override {
        enableLanguages = [
          "eng"
          "deu"
          "fra"
          "ita"
        ];
      })
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

  # Settings at a page and a row, for Search and people: <id>-settings [PAGE [ROW]]
  settingsCommand = pkgs.writeShellScriptBin "${id}-settings" ''
    exec ${lib.getExe' pkgs.quickshell "qs"} -c ${id} ipc call settings open "''${1:-home}" "''${2:-}"
  '';
  # Settings among the apps, like any other
  settingsEntry = pkgs.makeDesktopItem {
    name = "${id}-settings";
    desktopName = "Settings";
    comment = "Themes, network, sound, display, input, power, hotkeys, versions";
    exec = "${id}-settings";
    icon = "preferences-system";
    categories = [ "Settings" ];
  };

  qmlPath = "/run/current-system/sw/share/${id}-ui/qml";

  # PATH for user services that start programs: the user's profiles, the setuid wrappers, the system
  sessionPath = lib.concatStringsSep ":" [
    "%h/.nix-profile/bin"
    "/etc/profiles/per-user/%u/bin"
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
  ];
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/quickshell/${id}".source = ../../shell/qml;

    # The search service behind Search and the cheat sheet
    ${id}.search.enable = true;

    # The password of the lock screen
    security.pam.services."${id}-lock" = { };

    environment.systemPackages =
      with pkgs;
      [
        settingsCommand
        settingsEntry
        captureCommand
        monitorCommand
        btop
        libnotify
        quickshell
        wl-clipboard
        grim
        slurp
        hyprpicker
        brightnessctl
        playerctl
        cava
      ]
      ++ lib.optionals (!cfg.live) [ cliphist ];

    # The sound as bars for the clock of the desktop and the media player (Spectrum.qml): cava
    # reads PipeWire and writes one line of 48 numbers (0 to 100) per frame
    environment.etc."xdg/${id}/cava.conf".text = ''
      [general]
      bars = 48
      framerate = 30
      autosens = 1
      [input]
      method = pipewire
      source = auto
      [output]
      method = raw
      raw_target = /dev/stdout
      data_format = ascii
      ascii_max_range = 100
      bar_delimiter = 59
      frame_delimiter = 10
      [smoothing]
      noise_reduction = 77
    '';

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
      restartTriggers = [
        ui
        ../../shell/qml
      ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.quickshell "qs"} -c ${id}";
        Restart = "on-failure";
        RestartSec = 1;
        # Apps started from the bar, Search and Settings outlive a restart of the shell (an update
        # restarts it)
        KillMode = "process";
      };
    };

    # The first login shows the cheat sheet once: the keys are all one needs to know
    systemd.user.services."${id}-welcome" = lib.mkIf (!cfg.live) {
      description = "Show the cheat sheet at the first login";
      partOf = [ "graphical-session.target" ];
      after = [ "${id}-shell.service" ];
      wantedBy = [ "graphical-session.target" ];
      path = [
        pkgs.quickshell
        pkgs.coreutils
      ];
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

    # The clipboard history behind Super V: text and pictures, kept by cliphist
    systemd.user.services."${id}-clipboard" = lib.mkIf (!cfg.live) {
      description = "Keep a history of the clipboard";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      path = [
        pkgs.wl-clipboard
        pkgs.cliphist
      ];
      script = ''
        wl-paste --type text --watch cliphist store &
        exec wl-paste --type image --watch cliphist store
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
