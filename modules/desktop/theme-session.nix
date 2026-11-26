# The session has its own theme on top of the machine's (Q14): the user service
# <id>-theme-session (`<id>-theme session`) shows another god every 10 minutes unless kept,
# writes tokens.json, hyprland.lua, ghostty, btop.theme, starship.toml and the files for GTK and
# Zen into $XDG_RUNTIME_DIR/<id>/theme and reloads Hyprland, Ghostty and btop; the folders of
# Files and the pointer take the god's colours (built per god, picked by the hook). Choosing a theme
# by hand in the picker sets the machine's theme through pkexec; polkit lets the active local
# session do that, and only that, without a password.
{
  config,
  lib,
  pkgs,
  distroFlake,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;

  themeCommand = lib.getExe config.${id}.theme.package;

  # How often the session changes its theme: theme-cycle of the design system (600s)
  tokens = lib.importJSON "${distroFlake.inputs.strixui}/design-system/tokens.json";
  tokenCycle =
    (lib.findFirst (t: t.name == "theme-cycle") { value = "600s"; } tokens.duration.tokens).value;

  cyclePeriod = cfg.themeCycle;

  # The symbols of Files and every GTK app: Papirus, and for every god a small theme on top of it
  # whose folders have the color nearest to the god's (Papirus draws its folders in these colors)
  folderColors = {
    saturnus = "carmine";
    janus = "teal";
    apollo = "palebrown";
    mars = "deeporange";
    vulcanus = "green";
    neptunus = "bluegrey";
    pluto = "violet";
    bacchus = "red";
  };
  iconThemes = pkgs.runCommand "${id}-icons" { } (
    lib.concatStrings (
      lib.mapAttrsToList (god: color: ''
        papirus=${pkgs.papirus-icon-theme}/share/icons
        theme=$out/share/icons/${branding.name}-${god}
        mkdir -p $theme
        sed -e 's/^Name=.*/Name=${branding.name} ${god}/' -e 's/^Inherits=.*/Inherits=Papirus-Dark,Adwaita,hicolor/' \
          $papirus/Papirus-Dark/index.theme >$theme/index.theme
        found=0
        for file in $papirus/Papirus/*/places/folder-${color}*.svg; do
          size=''${file#$papirus/Papirus/}
          size=''${size%%/*}
          name=''${file##*/}
          mkdir -p $theme/$size/places
          ln -s $file $theme/$size/places/folder''${name#folder-${color}}
          found=1
        done
        [ $found = 1 ] || { echo "Papirus has no folders in ${color}"; exit 1; }
      '') folderColors
    )
  );

  # The pointer of every god: Bibata with a body in a deep shade of the god's accent and a rim in
  # its text colour, made by the theme engine (cursor). The hook shows the one of the god shown;
  # a theme from a repository keeps Bibata.
  bibata = "${pkgs.bibata-cursors}/share/icons/Bibata-Modern-Classic";
  cursorThemes = pkgs.runCommand "${id}-cursors" { } (
    lib.concatMapStrings (god: ''
      ${themeCommand} cursor ${god} ${bibata} $out/share/icons/${branding.name}-${god}-cursor \
        --themes ${config.system.build.themes} --name ${lib.escapeShellArg "${branding.name} ${god}"}
    '') (lib.attrNames folderColors)
  );
  # After every change of the session's theme: Hyprland and every Ghostty window read their
  # colors again, and GTK apps take the folders and the pointer of the god
  sessionHook = pkgs.writeShellScript "${id}-theme-reload" ''
    theme=$(${lib.getExe pkgs.jq} -r '.theme // ""' "$XDG_RUNTIME_DIR/${id}/theme/tokens.json" 2>/dev/null)
    icons=Papirus-Dark
    if [ -n "$theme" ] && [ -d "${iconThemes}/share/icons/${branding.name}-$theme" ]; then
      icons="${branding.name}-$theme"
    fi
    cursor=Bibata-Modern-Classic
    if [ -n "$theme" ] && [ -d "/run/current-system/sw/share/icons/${branding.name}-$theme-cursor" ]; then
      cursor="${branding.name}-$theme-cursor"
    fi
    ${lib.getExe pkgs.dconf} write /org/gnome/desktop/interface/icon-theme "'$icons'" || true
    ${lib.getExe pkgs.dconf} write /org/gnome/desktop/interface/cursor-theme "'$cursor'" || true
    # Hyprland's socket may not answer in time while it is busy (software rendering): try for
    # up to two minutes; this runs beside the session service and holds nothing up
    for try in 1 2 3 4 5 6 7 8 9 10; do
      ${config.programs.hyprland.package}/bin/hyprctl reload && break
      echo "hyprctl reload failed ($try)"
      sleep 3
    done
    # Hyprland draws the pointer for every app; a reload keeps the one it had
    ${config.programs.hyprland.package}/bin/hyprctl setcursor "$cursor" 24 || true
    ${pkgs.procps}/bin/pkill -USR2 -x ghostty || true
    ${pkgs.procps}/bin/pkill -USR2 -x btop || true
  '';
in
{
  options.${id}.desktop = {
    themeCycle = lib.mkOption {
      type = lib.types.strMatching "[0-9]+s";
      default = tokenCycle;
      defaultText = lib.literalExpression ''"600s" (theme-cycle of StrixUI)'';
      description = "How often the session moves on to another god, unless the theme is kept.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.optionals (!cfg.live) [
      pkgs.papirus-icon-theme
      iconThemes
      cursorThemes
    ];

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
        # The prompt's configuration, written again in the colors of the god (modules/apps/prompt.nix)
        PROMPT_BASE = "${../../shell/starship.toml}";
        # The shape and the settings of Zen: the file of ${branding.name}, then the user's own
        BROWSER_BASE = "${../../shell/browser.toml}";
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
    '';
  };
}
