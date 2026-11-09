# Graphical boot with Plymouth: wordmark, a red progress line and a styled
# field for the LUKS passphrase instead of lines of text.
#
# Plymouth runs in the initrd. A new theme therefore only takes effect after
# a rebuild with "boot" and a reboot, not right away.
# Pressing Esc during boot shows the text messages behind it.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.boot.splash;
in
{
  options.${branding.id}.boot.splash = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Graphical boot splash with Plymouth and a quiet boot without text messages.";
    };

    theme = lib.mkOption {
      type = lib.types.attrs;
      default = import ../themes/strix.nix;
      defaultText = lib.literalExpression "import ./themes/strix.nix";
      description = "Theme data the Plymouth theme is generated from.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = branding.id;
      themePackages = [ (pkgs.callPackage ../packages/plymouth-theme { } { inherit (cfg) theme; }) ];
      # One font file for all text in the initrd
      font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
    };

    # Quiet boot: no kernel or udev messages on top of the splash.
    # (boot.initrd.verbose is gone, the systemd initrd is quiet with "quiet".)
    boot.consoleLogLevel = 3;
    boot.kernelParams = [
      "quiet"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    # Boot menu only while a key (e.g. space) is held during boot
    boot.loader.timeout = lib.mkDefault 0;
  };
}
