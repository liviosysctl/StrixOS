# Apps from Flathub, for what nixpkgs does not have: `flatpak install flathub <app>` installs one for
# the machine (it asks for the password), Search finds it like every other app, and <id>-update
# updates them with the system. Flatpak apps run in a sandbox; they may read the colors of the
# session's theme (gtk.css and the files it links to), so GTK apps from Flathub look like the rest.
{
  config,
  lib,
  ...
}:
let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;
  flatpak = lib.getExe config.services.flatpak.package;
in
{
  config = lib.mkIf (cfg.enable && !cfg.live) {
    services.flatpak.enable = true;
    # Flatpak turns on the X11 font folder, which XWayland would be built anew for; Strix runs
    # Hyprland without XWayland, so it keeps the one of the binary cache
    programs.xwayland.defaultFontPath = "";
    # Search watches the folder of the apps; it has to be there before the first app is
    systemd.tmpfiles.rules = [ "d /var/lib/flatpak/exports/share/applications 0755 root root -" ];

    # Flathub is added once the machine is online, by a timer: a unit after network-online.target
    # that the boot waits for would hold up the login until the network is there
    systemd.services."${id}-flathub" = {
      description = "Add Flathub to Flatpak and give its apps the theme";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${flatpak} remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
          "${flatpak} override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-run/${id}/theme:ro"
        ];
        # Offline at boot: again a minute later
        Restart = "on-failure";
        RestartSec = 60;
      };
    };
    systemd.timers."${id}-flathub" = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "1min";
    };
  };
}
