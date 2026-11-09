# Graphical boot with Plymouth: wordmark, an activity line and a styled
# field for the LUKS passphrase instead of lines of text.
#
# The look comes from the theme: modules/theme.nix builds a Plymouth theme
# per theme variant and picks the one of the selected theme at every boot.
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
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
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
