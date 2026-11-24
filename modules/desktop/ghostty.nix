# Ghostty, the terminal: the look of the distribution and the colors of the session's theme.
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

  # Copied once into a new user's ~/.config/ghostty/config, then theirs to change
  ghosttyUser = pkgs.writeText "ghostty-config" ''
    # Made by ${branding.name} for you; change it as you like.
    # The look of ${branding.name} first, then the colors of the current theme, which follow every
    # switch (strix-theme is a link to the session's colors). Remove a line to keep your own.
    config-file = ?/etc/xdg/${id}/ghostty/defaults
    config-file = ?${id}-theme
  '';

  ghosttyDefaults = pkgs.writeText "ghostty-defaults" ''
    # The look of ${branding.name} (modules/desktop/ghostty.nix)
    font-family = BlexMono Nerd Font Mono
    font-style = SemiBold
    font-style-bold = Bold
    font-size = 13
    # Smoked glass: the compositor blurs what lies behind the terminal
    background-opacity = 0.72
    window-padding-x = 12
    window-padding-y = 8
    window-decoration = none
    gtk-titlebar = false
    confirm-close-surface = false
    cursor-style = bar
    # The terminal waits in the background from the login on (its service, below) and stays
    # there when its last window is closed: a new window is there at once
    quit-after-last-window-closed = false
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/${id}/ghostty/defaults".source = ghosttyDefaults;
    environment.etc."xdg/${id}/ghostty/user".source = ghosttyUser;

    environment.systemPackages = [ pkgs.ghostty ];

    # Starting the terminal takes about a second: its toolkit, the fonts, the graphics card.
    # Ghostty brings a service that pays that once, at the login, with no window; every
    # `ghostty` after it only asks the one that runs for a new window.
    systemd.packages = [ pkgs.ghostty ];
    systemd.user.services."app-com.mitchellh.ghostty" = {
      wantedBy = [ "graphical-session.target" ];
      # Every window is a child of this service, and NixOS gives a user service only a handful
      # of tools on PATH: without the session's own, no command is found in the terminal
      environment.PATH = lib.mkForce (
        lib.concatStringsSep ":" [
          "%h/.nix-profile/bin"
          "/etc/profiles/per-user/%u/bin"
          "/run/wrappers/bin"
          "/run/current-system/sw/bin"
        ]
      );
    };

    # A new user gets the Ghostty config that follows the theme, copied once and then theirs to
    # change. The link to the session's colors is made again at every login.
    systemd.user.tmpfiles.rules = [
      "C %h/.config/ghostty/config 0644 - - - /etc/xdg/${id}/ghostty/user"
      "L+ %h/.config/ghostty/${id}-theme - - - - %t/${id}/theme/ghostty"
    ];
  };
}
