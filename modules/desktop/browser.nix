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

    # Firefox fetches Widevine, the module streaming services ask for, by itself once it has
    # been started. The browser of Strix finds it in Firefox's profile and uses the same one,
    # so nothing that is not free is part of the system.
    programs.firefox = lib.mkIf (!cfg.live) {
      enable = true;
      policies.EncryptedMediaExtensions = {
        Enabled = true;
        Locked = false;
      };
    };

    # Video is decoded by the graphics card where it can be. Mesa brings the drivers for that
    # for most cards; Intel's newer ones need this one.
    hardware.graphics.extraPackages = lib.mkIf (!cfg.live) [ pkgs.intel-media-driver ];
  };
}
