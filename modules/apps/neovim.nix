# Neovim, the editor of the terminal, in the colors of the god (shell/nvim).
#
# The colorscheme <id> reads tokens.json of the theme engine, the session's
# first, else the machine's, and every open Neovim takes the new colors when
# the god changes. It is installed system-wide (/etc/xdg/nvim), so a user's
# own init.lua still runs; a colorscheme chosen there wins.
#
# Beside the colors it is set up for a first day in Neovim (plugin/editor.lua):
# Space opens a menu of every key, a file finder and a file tree, completion,
# a start page and a cheat sheet (Space ?). The Nix configuration of the
# machine is a key away (Space n), and saving a file of root asks for the
# password. That part steps aside as soon as there is an init.lua in
# ~/.config/nvim. plugin/languages.lua sets up the language servers: Nix with
# the options of the machine, Lua with Hyprland's functions, TOML.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.neovim;

  names = {
    inherit id;
    inherit (branding) name;
  };
  fill = file: pkgs.replaceVars file (names // { runtimeDir = "/run/${id}/theme"; });
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
        "colors/${id}.lua".source = fill ../../shell/nvim/colors/theme.lua;
        "plugin/${id}.lua".source = fill ../../shell/nvim/plugin/theme.lua;
        "plugin/${id}-editor.lua".source = pkgs.replaceVars ../../shell/nvim/plugin/editor.lua (
          # Where the tools keep the machine's configuration (modules/core/tools.nix)
          names // { configDir = "/etc/nixos"; }
        );
        # The language servers: Nix, Lua (with the descriptions of Hyprland's functions), TOML
        "plugin/${id}-languages.lua".source = pkgs.replaceVars ../../shell/nvim/plugin/languages.lua {
          inherit id;
          configDir = "/etc/nixos";
          hyprStubs =
            lib.optionalString config.${id}.desktop.enable
              "${config.programs.hyprland.package}/share/hypr/stubs";
        };
        "${id}/cheatsheet.txt".source = ../../shell/nvim/cheatsheet.txt;
      };
      # Only plugins and no customRC: the wrapper then leaves the user's init alone
      configure.packages.${id}.start = with pkgs.vimPlugins; [
        which-key-nvim
        telescope-nvim
        plenary-nvim
        neo-tree-nvim
        nui-nvim
        nvim-web-devicons
        lualine-nvim
        bufferline-nvim
        gitsigns-nvim
        mini-nvim
        blink-cmp
        alpha-nvim
        (nvim-treesitter.withPlugins (
          p: with p; [
            bash
            c
            cpp
            css
            html
            javascript
            json
            lua
            markdown
            markdown_inline
            nix
            python
            qmljs
            query
            regex
            rust
            toml
            typescript
            vim
            vimdoc
            yaml
          ]
        ))
      ];
    };

    # Nix files: mistakes and the options shown while typing (nixd), formatted on saving (nixfmt)
    environment.systemPackages = [
      pkgs.nixd
      pkgs.nixfmt
      pkgs.lua-language-server
      pkgs.taplo
    ];
  };
}
