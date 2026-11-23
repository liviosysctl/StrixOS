# The browser: the one of Strix (flake input strix-browser), whose window is drawn like the
# shell and into which the search grows. Firefox is there beside it, plain, for the page that
# needs another browser; Search finds it among the apps.
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

  browser = distroFlake.inputs.strix-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  config = lib.mkIf cfg.enable {
    # Links, web pages and PDFs open in the browser; the live session of the ISO has none
    xdg.mime.defaultApplications = lib.mkIf (!cfg.live) (
      lib.genAttrs [
        "text/html"
        "application/xhtml+xml"
        "application/pdf"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ] (_: "strix-browser.desktop")
    );

    environment.sessionVariables.BROWSER = lib.mkIf (!cfg.live) "strix-browser";

    environment.systemPackages = lib.optionals (!cfg.live) [ browser ];

    programs.firefox.enable = lib.mkIf (!cfg.live) true;
  };
}
