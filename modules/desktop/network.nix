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

  # Tailscale from the Wi-Fi panel: <id>-tailnet on|off|state. Turning it on for the first time
  # opens the page where the machine joins the tailnet.
  tailnetCommand = pkgs.writeShellApplication {
    name = "${id}-tailnet";
    runtimeInputs = [
      config.services.tailscale.package
      pkgs.jq
      pkgs.xdg-utils
      pkgs.libnotify
    ];
    text = ''
      state() { tailscale status --json 2>/dev/null | jq -r '.BackendState // "Stopped"' || echo Stopped; }
      case "''${1:-state}" in
        state) if [ "$(state)" = Running ]; then echo on; else echo off; fi ;;
        off) tailscale down ;;
        on)
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

    environment.systemPackages = lib.optionals (!cfg.live) [ tailnetCommand ];
  };
}
