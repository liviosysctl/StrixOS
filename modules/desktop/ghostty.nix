# Ghostty, the terminal: the look of the distribution and the colors of the session's theme.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  id = branding.id;
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
    font-family = GeistMono Nerd Font Mono
    font-style = SemiBold
    font-style-bold = ExtraBold
    font-size = 13
    window-padding-x = 12
    window-padding-y = 8
    window-decoration = none
    gtk-titlebar = false
    confirm-close-surface = false
    cursor-style = bar
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/${id}/ghostty/defaults".source = ghosttyDefaults;
    environment.etc."xdg/${id}/ghostty/user".source = ghosttyUser;

    environment.systemPackages = [ pkgs.ghostty ];

    # A new user gets the Ghostty config that follows the theme; an existing one stays. The link to
    # the session's colors is made every time. Users without a home of their own are left alone.
    systemd.user.services."${id}-ghostty-config" = {
      description = "Give Ghostty the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        mkdir -p "$HOME/.config/ghostty"
        [ -e "$HOME/.config/ghostty/config" ] || install -m 0644 /etc/xdg/${id}/ghostty/user "$HOME/.config/ghostty/config"
        ln -sfn "$XDG_RUNTIME_DIR/${id}/theme/ghostty" "$HOME/.config/ghostty/${id}-theme"
      '';
    };
  };
}
