# Was jede installierte Maschine bekommt, unabhängig von den Antworten im Installer.
{ config, lib, distroFlake, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id};
in
{
  options.${branding.id}.user = {
    name = lib.mkOption {
      type = lib.types.strMatching "^[a-z_][a-z0-9_-]{0,31}$";
      example = "livio";
      description = "Login-Name des Hauptbenutzers.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Livio";
      description = "Anzeigename, erscheint beim Login.";
    };
  };

  config = {
    # Bootloader
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 10; # 1 GiB ESP reicht dafür locker
    boot.loader.efi.canTouchEfiVariables = true;

    # Nix. Die Registry für nixpkgs setzt nixosSystem schon selbst.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.settings.auto-optimise-store = true;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Quellen der Distro und ihrer Inputs bleiben im Store, damit /etc/nixos
    # ohne Netz neu gebaut werden kann.
    system.extraDependencies = [ distroFlake.outPath ]
      ++ map (input: input.outPath) (lib.attrValues distroFlake.inputs);

    networking.networkmanager.enable = true;

    # Das Passwort steht nicht in der Config (es landete sonst lesbar im Store).
    # Der Installer setzt es einmal mit chpasswd, danach liegt es in /etc/shadow.
    users.mutableUsers = lib.mkDefault true;
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      inherit (cfg.user) description;
      extraGroups = [ "wheel" "networkmanager" ];
    };
    security.sudo.wheelNeedsPassword = true;
  };
}
