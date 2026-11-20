# Power: the battery and the power profiles of the bar, what closing the lid does, what happens
# when nobody is at the machine (hypridle, with the times of Settings › Power), and the night
# light.
{ config, lib, pkgs, ... }:

let
  branding = import ../../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;

  # The night light: warmer colors in the evening (hyprsunset, from 20:00 to 7:00), and by hand
  # until the next of those hours: <id>-nightlight on|off|toggle|state
  nightTemperature = 4500;
  nightlightCommand = pkgs.writeShellApplication {
    name = "${id}-nightlight";
    runtimeInputs = [ config.programs.hyprland.package pkgs.coreutils ];
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

  # What happens when nobody is at the machine: <id>-idle, which runs hypridle with the times of
  # ~/.config/<id>/idle.json (Settings › Power), apart for power and battery, and keeps awake
  idleCommand = pkgs.writeShellApplication {
    name = "${id}-idle";
    runtimeInputs = with pkgs; [
      hypridle
      jq
      coreutils
      brightnessctl
      systemd
      quickshell
      config.programs.hyprland.package
    ];
    runtimeEnv.ID = id;
    text = builtins.readFile ../../shell/bin/idle.sh;
  };
in
{
  options.${id}.desktop = {
    lid = lib.mkOption {
      type = lib.types.enum [ "suspend" "hibernate" "lock" "ignore" ];
      default = "suspend";
      description = ''
        What closing the lid does on battery and on power: suspend (the default), hibernate
        (needs a swap file large enough, strix.storage.hibernation), lock the screen, or nothing.
        With an external screen connected nothing happens either way. Settings › Power shows it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The battery in the bar and the power profiles of Settings
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # Closing the lid (Settings › Power shows it); locking comes from hypridle before sleep
    services.logind.settings.Login = {
      HandleLidSwitch = cfg.lid;
      HandleLidSwitchExternalPower = cfg.lid;
      HandleLidSwitchDocked = "ignore";
    };
    environment.etc."xdg/${id}/lid".text = cfg.lid + "\n";

    environment.systemPackages = [ pkgs.hypridle ] ++ lib.optionals (!cfg.live) [
      nightlightCommand
      idleCommand
    ];

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
  };
}
