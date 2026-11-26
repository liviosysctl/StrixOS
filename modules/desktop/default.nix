# The desktop (12-desktop in the plan): Hyprland with the shell of the distribution, the login,
# the theme of the session, sound, power, files and the apps of the cheat sheet. Every part is a
# file of its own; all of them are on while <id>.desktop.enable is.
{ lib, ... }:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
in
{
  imports = [
    ./ui.nix
    ./search.nix
    ./theme.nix
    ./theme-session.nix
    ./hyprland.nix
    ./login.nix
    ./shell.nix
    ./look.nix
    ./audio.nix
    ./power.nix
    ./network.nix
    ./files.nix
    ./printing.nix
    ./passwords.nix
    ./update-check.nix
    ./ghostty.nix
    ./browser.nix
    ./default-apps.nix
  ];

  options.${id}.desktop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The desktop: Hyprland, the login, sound and the apps of the cheat sheet.";
    };

    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
      description = ''
        The live session of the ISO (iso/live.nix): logged in at once as nixos, never locked,
        without the apps of an installed machine.
      '';
    };
  };
}
