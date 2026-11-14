# The live session of the ISO: a slim Strix desktop the stick starts into, with
# the graphical installer (installer/gui) in front.
#
# greetd logs nixos in at once; the installer window opens as soon as the
# session is up. Closing it only hides it: a card in the middle of the desktop
# ("Install Strix") opens it again, and so does Search (Super Space, "Install").
# The console installer stays: sudo strix-install on any console (Ctrl+Alt+F2).
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  system = pkgs.stdenv.hostPlatform.system;
  installer = distroFlake.packages.${system}.${if config.${id}.iso.dev then "installer-dev" else "installer"};
  gui = pkgs.callPackage ../installer/gui { inherit installer; };
  qs = lib.getExe' pkgs.quickshell "qs";
  open = "${qs} -c ${id}-installer ipc call installer open";
in
{
  imports = [
    ../modules/ui.nix
    ../modules/search.nix
    ../modules/desktop.nix
  ];

  ${id}.desktop = {
    live = true;
    # The window floats in the middle at its own size instead of being tiled
    extraConfig = ''
      hl.window_rule({
          name = "${id}-installer",
          match = { title = "^Installer$" },
          float = true,
          center = true,
          size = "1040 700",
      })
    '';
  };

  # The minimal ISO profile turns these off; the desktop needs them
  xdg.icons.enable = true;
  xdg.mime.enable = true;

  # Speech synthesis with its voices, and gvfs with samba: nothing in the live session uses them,
  # and the ISO must stay under 2 GiB (iso/default.nix)
  services.speechd.enable = false;
  services.gvfs.enable = lib.mkForce false;

  # Typing in the session starts with the same layout as the console (Swiss German); the
  # installer's first page switches it
  services.xserver.xkb.layout = "ch";

  environment.etc."xdg/quickshell/${id}-installer".source = "${gui}/share/${id}-installer/qml";

  # The back end: knows the computer, installs through sudo (the live user may)
  systemd.user.services."${id}-installer" = {
    description = "The back end of the graphical installer";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    unitConfig.ConditionUser = "nixos";
    environment.SOCKET = "%t/${id}/install.sock";
    serviceConfig = {
      ExecStart = lib.getExe gui;
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # The window, at once; started again if it ever stops
  systemd.user.services."${id}-installer-ui" = {
    description = "The window of the graphical installer";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    unitConfig.ConditionUser = "nixos";
    environment.QML_IMPORT_PATH = "/run/current-system/sw/share/${id}-ui/qml";
    serviceConfig = {
      ExecStart = "${qs} -c ${id}-installer";
      Restart = "always";
      RestartSec = 1;
    };
  };

  # "Install Strix" in Search and app lists
  environment.systemPackages = [
    (pkgs.makeDesktopItem {
      name = "${id}-install";
      desktopName = "Install ${branding.name}";
      comment = "Install ${branding.name} on this computer";
      exec = open;
      icon = "system-software-install";
      categories = [ "System" ];
    })
  ];
}
