# What every app looks like before the theme colors it: the pointer, the symbols, the fonts, dark
# GTK and Qt. GTK and Qt apps then take the colors of the session's theme from its files.
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

  # The pointer: Bibata; the ISO keeps the one GTK brings, for its size
  cursorTheme = if cfg.live then "Adwaita" else "Bibata-Modern-Classic";
in
{
  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      XCURSOR_THEME = cursorTheme;
      XCURSOR_SIZE = "24";
    };

    programs.dconf = {
      enable = true;
      # Every god is dark: GTK and libadwaita apps follow. adw-gtk3 makes GTK 3 apps look like
      # libadwaita and read the same named colors, so both take the god's colors from gtk.css
      profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-theme = "adw-gtk3-dark";
            cursor-theme = cursorTheme;
            icon-theme = if cfg.live then "Adwaita" else "Papirus-Dark";
            monospace-font-name = "IBM Plex Mono 11";
          };
        }
      ];
    };

    # Noto for text in every script; IBM Plex Mono with the Nerd Font icons (BlexMono) for the terminal and its
    # prompt
    fonts.packages = [
      pkgs.noto-fonts
      pkgs.nerd-fonts.blex-mono
    ]
    # Chinese, Japanese and Korean, which Noto keeps apart: without them a page in those scripts is
    # boxes. Large, so not on the ISO.
    ++ lib.optionals (!cfg.live) [ pkgs.noto-fonts-cjk-sans ];

    environment.systemPackages =
      with pkgs;
      [
        adwaita-icon-theme
        adw-gtk3
      ]
      ++ lib.optionals (!cfg.live) [ bibata-cursors ];

    # Qt apps take the look from qt6ct and qt5ct: the palette of the session's theme (below) and
    # the symbols of GTK
    qt = lib.mkIf (!cfg.live) {
      enable = true;
      platformTheme = "qt5ct";
    };

    # Both read the colors of the session's theme from its files, through what is made here at a
    # login and only where the user has nothing of their own: the link from GTK's gtk.css (apps
    # read it when they start) and the settings of qt6ct and qt5ct, which name the palette by its
    # whole path.
    systemd.user.tmpfiles.rules = [
      "L %h/.config/gtk-3.0/gtk.css - - - - %t/${id}/theme/gtk3.css"
      "L %h/.config/gtk-4.0/gtk.css - - - - %t/${id}/theme/gtk4.css"
    ]
    ++ lib.optionals (!cfg.live) (
      map
        (
          version:
          "f %h/.config/qt${version}ct/qt${version}ct.conf 0644 - - - "
          + "[Appearance]\\ncolor_scheme_path=%t/${id}/theme/qt${version}.conf\\n"
          + "custom_palette=true\\nicon_theme=Papirus-Dark\\nstyle=Fusion\\n"
        )
        [
          "6"
          "5"
        ]
    );
  };
}
