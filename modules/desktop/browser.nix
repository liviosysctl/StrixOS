# The browser: Zen, in the colors of the session's theme and the shape of shell/browser.toml.
{
  config,
  lib,
  pkgs,
  distroFlake,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;

  # The browser: Zen, the only one installed (flake input zen-browser, not in nixpkgs)
  # It reads userChrome.css of the profile, where the colors of the theme arrive (see the
  # <id>-zen-colors service); Zen leaves that switched off by itself.
  zen = distroFlake.inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraPolicies.Preferences."toolkit.legacyUserProfileCustomizations.stylesheets" = {
      Value = true;
      Status = "default";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    # Links, web pages and PDFs open in Zen; the live session of the ISO has no browser
    xdg.mime.defaultApplications = lib.mkIf (!cfg.live) (
      lib.genAttrs [
        "text/html"
        "application/xhtml+xml"
        "application/pdf"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ] (_: "zen-beta.desktop")
    );

    environment.sessionVariables.BROWSER = lib.mkIf (!cfg.live) "zen-beta";

    environment.systemPackages = lib.optionals (!cfg.live) [ zen ];

    # Video is decoded by the graphics card where it can be. Mesa brings the drivers for that
    # for most cards; Intel's newer ones need this one.
    hardware.graphics.extraPackages = lib.mkIf (!cfg.live) [ pkgs.intel-media-driver ];

    # Zen takes the god's colors from the session's zen-userChrome.css and zen-userContent.css,
    # linked into chrome/ of every profile, and its settings from zen-user.js, linked as user.js.
    # As with GTK, a file of the user's own stays. Zen makes its profile at its first start, so
    # the path unit links it then; Zen reads the files when it starts, so they show from the
    # next start on.
    systemd.user.services."${id}-zen-colors" = {
      description = "Give Zen the colors of the session's theme";
      wantedBy = [ "default.target" ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.gnused
      ];
      script = ''
        [ -w "$HOME" ] || exit 0
        for ini in "$HOME/.config/zen/profiles.ini" "$HOME/.zen/profiles.ini"; do
          [ -r "$ini" ] || continue
          sed -n 's/^Path=//p' "$ini" | while IFS= read -r path; do
            case "$path" in
              /*) profile=$path ;;
              *) profile=''${ini%/*}/$path ;;
            esac
            [ -d "$profile" ] || continue
            mkdir -p "$profile/chrome"
            for name in chrome/userChrome.css chrome/userContent.css user.js; do
              target="$XDG_RUNTIME_DIR/${id}/theme/zen-''${name##*/}"
              file="$profile/$name"
              if [ -L "$file" ] && [ "$(readlink "$file")" = "$target" ]; then
                continue
              fi
              if [ -e "$file" ] || [ -L "$file" ]; then
                echo "$file is the user's own, left alone"
                continue
              fi
              ln -s "$target" "$file"
            done
          done
        done
      '';
    };
    systemd.user.paths."${id}-zen-colors" = {
      description = "Link the colors into a new Zen profile";
      wantedBy = [ "default.target" ];
      pathConfig.PathChanged = [
        "%h/.config/zen/profiles.ini"
        "%h/.zen/profiles.ini"
      ];
    };
  };
}
