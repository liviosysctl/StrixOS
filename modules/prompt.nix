# The prompt of bash and zsh: Starship with the segments of shell/starship.toml. Not on the
# text console (TERM=linux), which has no Nerd Font for the icons and the bar edges; there
# the plain prompt of NixOS stays. A user's own ~/.config/starship.toml wins.
{ config, lib, pkgs, ... }:

let
  init = shell: ''
    if [[ $TERM != dumb && $TERM != linux ]]; then
      if [[ ! -f "''${STARSHIP_CONFIG:-$HOME/.config/starship.toml}" ]]; then
        export STARSHIP_CONFIG=${../shell/starship.toml}
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
