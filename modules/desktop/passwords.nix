# Passwords: the keyring that opens with the login, the agent for SSH keys, and the window that
# asks for the password when an app needs more rights.
{ config, lib, pkgs, ... }:

let
  branding = import ../../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;
in
{
  config = lib.mkIf cfg.enable {
    # The keyring: apps keep their passwords in it, and it opens with the password of the login.
    # With it comes the agent for SSH keys, which asks for a passphrase once and keeps it there.
    services.gnome.gnome-keyring.enable = lib.mkIf (!cfg.live) true;
    security.pam.services.greetd.enableGnomeKeyring = lib.mkIf (!cfg.live) true;
    programs.ssh.extraConfig = lib.mkIf (!cfg.live) "AddKeysToAgent yes";

    security.polkit.enable = true;

    systemd.user.services.hyprpolkitagent = {
      description = "Asks for the password when an app needs more rights";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
      };
    };
  };
}
