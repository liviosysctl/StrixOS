# Printers: CUPS, with printers on the network found by themselves.
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
in
{
  config = lib.mkIf cfg.enable {
    # Printers: CUPS, with printers on the network found by themselves (IPP Everywhere through
    # Avahi), so most need no driver. "Print Settings" in Search adds one that is not found.
    services.printing.enable = lib.mkIf (!cfg.live) true;
    services.avahi = lib.mkIf (!cfg.live) {
      enable = true;
      nssmdns4 = true;
    };

    environment.systemPackages = lib.optionals (!cfg.live) [ pkgs.system-config-printer ];
    # "Print Settings" brings a tray applet that starts with every session and stays. Nothing
    # here shows it: the entry of the same name in /etc/xdg comes first and turns it off
    environment.etc."xdg/autostart/print-applet.desktop" = lib.mkIf (!cfg.live) {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Print Queue Applet
        Hidden=true
      '';
    };
  };
}
