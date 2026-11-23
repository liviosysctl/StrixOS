# The browser: Zen, as it comes.
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
  zen = distroFlake.inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
  };
}
