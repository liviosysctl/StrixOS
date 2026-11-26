# Files (Nautilus, Super E) and what it needs: other drives, phones and network shares, thumbnails,
# the folders of the home, and a terminal in the folder shown.
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

  # Drives that are plugged in are mounted by themselves (packages/desk); a locked one asks for
  # its passphrase in a terminal (udisksctl)
  automountCommand = (pkgs.callPackage ../../packages/desk { }).command "automount" [
    pkgs.libnotify
    pkgs.udisks
    pkgs.uwsm
  ];

  # Files › Scripts › Open in Ghostty: a terminal in the folder shown, or in the folder of the
  # first selected item. Nautilus gives the selection as paths, the folder only as a URI
  openInGhostty = pkgs.writeShellApplication {
    name = "open-in-ghostty";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
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
      # With a folder named it is a terminal of its own, which ends with its window
      exec ghostty --quit-after-last-window-closed=true --working-directory="$dir"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
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

    environment.systemPackages = lib.optionals (!cfg.live) [ pkgs.nautilus ];

    # Documents, Downloads, Pictures, Videos and the others exist from the first login on: Files
    # pins them at its left, screenshots and recordings have their place
    systemd.user.services."${id}-folders" = lib.mkIf (!cfg.live) {
      description = "Make the folders of the home";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe' pkgs.xdg-user-dirs "xdg-user-dirs-update"}";
      };
    };

    # A stick or a card that is plugged in is mounted by itself; the notification opens it in
    # the file manager that is chosen. A small program that waits on the system bus
    systemd.user.services."${id}-automount" = lib.mkIf (!cfg.live) {
      description = "Mount drives that are plugged in";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # <id>-defaults and the terminal come from the system
      environment.PATH = lib.mkForce (
        lib.concatStringsSep ":" [
          "/etc/profiles/per-user/%u/bin"
          "/run/wrappers/bin"
          "/run/current-system/sw/bin"
        ]
      );
      serviceConfig = {
        ExecStart = lib.getExe automountCommand;
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # "Open in Ghostty" among the scripts of Files: a link, made at a login where the user has no
    # script of that name of their own
    systemd.user.tmpfiles.rules = lib.optionals (!cfg.live) [
      "L \"%h/.local/share/nautilus/scripts/Open in Ghostty\" - - - - /etc/xdg/${id}/nautilus/open-in-ghostty"
    ];

    security.polkit.extraConfig = ''
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
