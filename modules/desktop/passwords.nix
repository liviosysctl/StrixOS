# Passwords: the keyring that opens with the login, the agent for SSH keys, and the window that
# asks for the password when an app needs more rights.
{
  config,
  lib,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;
in
{
  config = lib.mkIf cfg.enable {
    # The keyring: apps keep their passwords in it, and it opens with the password of the login.
    # With it comes the agent for SSH keys, which asks for a passphrase once and keeps it there.
    services.gnome.gnome-keyring.enable = lib.mkIf (!cfg.live) true;
    security.pam.services.greetd.enableGnomeKeyring = lib.mkIf (!cfg.live) true;
    programs.ssh.extraConfig = lib.mkIf (!cfg.live) "AddKeysToAgent yes";

    # The window that asks for the password when an app needs more rights is the shell's
    # (shell/qml/Authenticate.qml): Quickshell is the polkit agent of the session
    security.polkit.enable = true;
  };
}
