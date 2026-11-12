# The design system on the machine: the QML module, the wallpapers and the
# fonts (packages/ui, from StrixUI). The shell and every Linux app import the
# module from /run/current-system/sw, so a switch brings the new version
# without a new login of the environment variable.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.ui;
  share = "/share/${branding.id}-ui";
in
{
  options.${branding.id}.ui = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The design system: QML module, wallpapers and fonts.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.callPackage ../packages/ui { src = distroFlake.inputs.strixui; };
      defaultText = lib.literalExpression "the design system of StrixUI";
      description = "The design system package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.pathsToLink = [ share ];
    fonts.packages = [ cfg.package ];
    environment.sessionVariables.QML_IMPORT_PATH = "/run/current-system/sw${share}/qml";
  };
}
