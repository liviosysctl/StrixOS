# Bluetooth of Settings and the bar, and Tailscale from the Wi-Fi panel.
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
  tailscale = !cfg.live && config.services.tailscale.enable;

  # Tailscale from the Wi-Fi panel: <id>-tailnet on|off|state. Turning it on for the first time
  # opens the page where the machine joins the tailnet. Its daemon runs only while it is on: on
  # starts it, off stops it (the main user may, see the polkit rule below).
  tailnetCommand = pkgs.writeShellApplication {
    name = "${id}-tailnet";
    runtimeInputs = [
      config.services.tailscale.package
      config.systemd.package
      pkgs.jq
      pkgs.xdg-utils
      pkgs.libnotify
    ];
    text = ''
      state() { tailscale status --json 2>/dev/null | jq -r '.BackendState // "Stopped"' || echo Stopped; }
      case "''${1:-state}" in
        state) if [ "$(state)" = Running ]; then echo on; else echo off; fi ;;
        off)
          tailscale down || true
          systemctl stop tailscaled.service
          ;;
        on)
          systemctl start tailscaled.service
          tailscale up --timeout=5s >/dev/null 2>&1 || true
          if [ "$(state)" != Running ]; then
            url=$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // ""' || true)
            if [ -n "$url" ]; then
              notify-send --app-name=Network "Tailscale" "Sign in on the page that opens to join your tailnet"
              xdg-open "$url"
            fi
          fi
          ;;
        *) echo "Usage: $(basename "$0") on|off|state" >&2; exit 64 ;;
      esac
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
    };

    # Tailscale, off until it is turned on in the Wi-Fi panel; the main user may do that
    services.tailscale = lib.mkIf (!cfg.live) {
      enable = lib.mkDefault true;
      extraSetFlags = [ "--operator=${config.${id}.user.name}" ];
    };

    # Its daemon waits in memory only while Tailscale is on: <id>-tailnet starts and stops it,
    # and at boot it comes back when it was on as the machine went down
    systemd.services.tailscaled.wantedBy = lib.mkIf tailscale (lib.mkForce [ ]);
    systemd.services."${id}-tailnet" = lib.mkIf tailscale {
      description = "Start Tailscale when it was on";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.jq
        config.systemd.package
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        state=/var/lib/tailscale/tailscaled.state
        # Never turned on: nothing to start
        [ -s "$state" ] || exit 0
        # Whether it should run is in the settings of the current profile, base64 in the state;
        # no profile: never signed in. Settings that cannot be read start it, as it always did
        want=$(jq -r 'if has("_current-profile") then .[."_current-profile" | @base64d] | @base64d | fromjson | .WantRunning else false end' "$state" 2>/dev/null || true)
        [ "$want" != false ] || exit 0
        systemctl start --no-block tailscaled.service
      '';
    };
    security.polkit.extraConfig = lib.mkIf tailscale ''
      // The main user turns Tailscale on and off in the Wi-Fi panel, which starts and stops its
      // daemon
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "tailscaled.service" &&
            (action.lookup("verb") == "start" || action.lookup("verb") == "stop") &&
            subject.user == "${config.${id}.user.name}") {
          return polkit.Result.YES;
        }
      });
    '';

    environment.systemPackages = lib.optionals (!cfg.live) [ tailnetCommand ];
  };
}
