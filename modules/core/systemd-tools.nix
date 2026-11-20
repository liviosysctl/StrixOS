# Makes the systemd command line tools show the right thing on NixOS.
# Used by installed machines (modules/default.nix) and the live ISO.
{ config, lib, pkgs, ... }:

let
  # systemd 262 adds an emoji to the chassis line of hostnamectl whatever
  # SYSTEMD_EMOJI says (chassis_string_to_glyph in hostnamectl.c does not ask
  # emoji_enabled()). This wrapper drops it from the status output and passes
  # everything else straight through. hiPrio wins over systemd's own
  # hostnamectl in the system profile.
  hostnamectl = lib.hiPrio (
    pkgs.writeShellScriptBin "hostnamectl" ''
      real=${config.systemd.package}/bin/hostnamectl
      if [ "''${1:-status}" != status ]; then
        exec "$real" "$@"
      fi
      # Piped output loses its colors unless they are asked for
      if [ -t 1 ]; then
        export SYSTEMD_COLORS="''${SYSTEMD_COLORS:-1}"
      fi
      # The glyphs from chassis_string_to_glyph. Matched literally, because with
      # colors the line also has escape codes around the label.
      "$real" "$@" | ${pkgs.gnused}/bin/sed -E '/Chassis:/s/ (💻|🖥️|🖳|具|⌚|📱|💽|📦)//'
      exit "''${PIPESTATUS[0]}"
    ''
  );
in
{
  # No emoji in the output of the other systemd tools (systemctl, journalctl
  # and so on ask emoji_enabled()). sudo would drop the variable, so it is
  # kept explicitly.
  environment.variables.SYSTEMD_EMOJI = "0";
  security.sudo.extraConfig = ''
    Defaults env_keep += "SYSTEMD_EMOJI"
  '';

  environment.systemPackages = [ hostnamectl ];

  # localed only accepts a keymap it finds under /usr/share/keymaps and the
  # like, which NixOS does not have. It then threw away KEYMAP=sg from
  # /etc/vconsole.conf, and localectl showed "VC Keymap: (unset)" although
  # the console uses the layout. Point it at the keymaps of kbd.
  systemd.services.systemd-localed.environment.SYSTEMD_KEYMAP_DIRECTORIES =
    "${pkgs.kbd}/share/keymaps";
}
