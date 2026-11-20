# The login of the distribution: shell/greeter, Quickshell in cage under greetd, or tuigreet if
# chosen. Both start the same UWSM session as the session file of Hyprland.
{ config, lib, pkgs, ... }:

let
  branding = import ../../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;

  xkb = config.services.xserver.xkb;

  ui = config.${id}.ui.package;

  sessionCommand = "uwsm start -e -D Hyprland hyprland.desktop";

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
    export XCURSOR_THEME=${config.environment.sessionVariables.XCURSOR_THEME} XCURSOR_SIZE=24
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
in
{
  options.${id}.desktop = {
    greeter = lib.mkOption {
      type = lib.types.enum [ "strix" "tuigreet" ];
      default = "strix";
      description = "The login: the own one in Quickshell, or tuigreet in the console.";
    };
  };

  config = lib.mkIf cfg.enable {
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
      cp ${../../shell/greeter/shell.qml} $out/shell.qml
      cp ${../../shell/qml/Owl.qml} $out/Owl.qml
    '';

    systemd.tmpfiles.rules = lib.mkIf (cfg.greeter == "strix") [
      "d ${greeterState} 0750 greeter greeter -"
    ];
  };
}
