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
  id = branding.id;
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
            monospace-font-name = "JetBrains Mono 11";
          };
        }
      ];
    };

    # Noto for text in every script; Geist Mono with the Nerd Font icons for the terminal and its
    # prompt
    fonts.packages = [
      pkgs.noto-fonts
      pkgs.nerd-fonts.geist-mono
    ];

    environment.systemPackages =
      with pkgs;
      [
        adwaita-icon-theme
        adw-gtk3
      ]
      ++ lib.optionals (!cfg.live) [ bibata-cursors ];

    # Qt apps: qt6ct and qt5ct give them the palette of the session's theme (qt6.conf and qt5.conf
    # of the theme engine) and the symbols of GTK. Their settings are written once for a user,
    # because they name the palette by its whole path; an app takes new colors when it starts.
    qt = lib.mkIf (!cfg.live) {
      enable = true;
      platformTheme = "qt5ct";
    };

    systemd.user.services."${id}-qt-colors" = lib.mkIf (!cfg.live) {
      description = "Give Qt apps the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        for version in 6 5; do
          file="$HOME/.config/qt''${version}ct/qt''${version}ct.conf"
          [ ! -e "$file" ] || continue
          mkdir -p "''${file%/*}"
          printf '%s\n' "[Appearance]" \
            "color_scheme_path=$XDG_RUNTIME_DIR/${id}/theme/qt$version.conf" \
            "custom_palette=true" "icon_theme=Papirus-Dark" "style=Fusion" >"$file"
        done
      '';
    };

    # GTK 3 and GTK 4 apps take the god's colors from the session's gtk3.css and gtk4.css. The link
    # is made only where the user has no gtk.css of their own (or already has the link); apps read
    # the file when they start, so a running app keeps its colors until it is opened again
    systemd.user.services."${id}-gtk-colors" = {
      description = "Give GTK apps the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        [ -w "$HOME" ] || exit 0
        for version in 3 4; do
          target="$XDG_RUNTIME_DIR/${id}/theme/gtk$version.css"
          file="$HOME/.config/gtk-$version.0/gtk.css"
          mkdir -p "''${file%/*}"
          if [ -L "$file" ] && [ "$(readlink "$file")" = "$target" ]; then
            continue
          fi
          if [ -e "$file" ] || [ -L "$file" ]; then
            echo "$file is the user's own, left alone"
            continue
          fi
          ln -s "$target" "$file"
        done
      '';
    };
  };
}
