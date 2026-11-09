# Grafischer Start mit Plymouth: Wortmarke, rote Fortschrittslinie und ein
# gestaltetes Feld für die LUKS-Passphrase statt Textzeilen.
#
# Plymouth läuft in der initrd. Ein neues Theme greift darum erst nach
# einem Neubau mit "boot" und einem Neustart, nicht sofort.
# Mit Esc beim Start sieht man die Textmeldungen dahinter.
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
      description = "Grafischer Startbildschirm mit Plymouth und ruhiger Start ohne Textmeldungen.";
    };

    theme = lib.mkOption {
      type = lib.types.attrs;
      default = import ../themes/strix.nix;
      defaultText = lib.literalExpression "import ./themes/strix.nix";
      description = "Theme-Daten, aus denen das Plymouth-Theme erzeugt wird.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = branding.id;
      themePackages = [ (pkgs.callPackage ../packages/plymouth-theme { } { inherit (cfg) theme; }) ];
      # Eine Schriftdatei für alle Texte in der initrd
      font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
    };

    # Ruhiger Start: keine Kernel- und udev-Meldungen über dem Startbildschirm.
    # (boot.initrd.verbose gibt es nicht mehr, die systemd-initrd ist mit "quiet" ruhig.)
    boot.consoleLogLevel = 3;
    boot.kernelParams = [
      "quiet"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    # Bootmenü nur, wenn man beim Start eine Taste (z. B. Leertaste) gedrückt hält
    boot.loader.timeout = lib.mkDefault 0;
  };
}
