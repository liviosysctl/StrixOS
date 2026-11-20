# The prompt of bash and zsh: Starship with the segments of shell/starship.toml. Not on the
# text console (TERM=linux), which has no Nerd Font for the icons and the bar edges; there
# the plain prompt of NixOS stays. A user's own ~/.config/starship.toml wins.
#
# In the graphical session the theme engine writes the same file with the colors of the god
# into $XDG_RUNTIME_DIR/<id>/theme/starship.toml; Starship reads it at every prompt, so the
# bars change with the theme in shells that are already open. Elsewhere (SSH, before the
# session) shell/starship.toml as it is, in the colors of Saturnus.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  id = (import ../../branding.nix).id;
  init = shell: ''
    if [[ $TERM != dumb && $TERM != linux ]]; then
      if [[ ! -f "''${STARSHIP_CONFIG:-$HOME/.config/starship.toml}" ]]; then
        if [[ -n "''${XDG_RUNTIME_DIR:-}" && -f "$XDG_RUNTIME_DIR/${id}/theme/starship.toml" ]]; then
          export STARSHIP_CONFIG="$XDG_RUNTIME_DIR/${id}/theme/starship.toml"
        else
          export STARSHIP_CONFIG=${../../shell/starship.toml}
        fi
      fi
      eval "$(${lib.getExe pkgs.starship} init ${shell} --print-full-init)"
    fi
  '';
in
{
  environment.systemPackages = [ pkgs.starship ];
  programs.bash.promptInit = lib.mkAfter (init "bash");
  programs.zsh.promptInit = lib.mkIf config.programs.zsh.enable (lib.mkAfter (init "zsh"));
}
