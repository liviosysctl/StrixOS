# Neovim, the editor of the terminal, in the colors of the god (shell/nvim).
#
# The colorscheme <id> reads tokens.json of the theme engine, the session's
# first, else the machine's, and every open Neovim takes the new colors when
# the god changes. It is installed system-wide (/etc/xdg/nvim), so a user's
# own init.lua still runs; a colorscheme chosen there wins.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;
  cfg = config.${id}.neovim;

  fill =
    file:
    pkgs.replaceVars file {
      inherit id;
      inherit (branding) name;
      runtimeDir = "/run/${id}/theme";
    };
in
{
  options.${id}.neovim.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Neovim as the default editor, in the colors of the theme.";
  };

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      runtime = {
        "colors/${id}.lua".source = fill ../shell/nvim/colors/theme.lua;
        "plugin/${id}.lua".source = fill ../shell/nvim/plugin/theme.lua;
      };
    };
  };
}
