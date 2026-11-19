# The tools of the terminal, set up for every user: eza and bat in place of plain listings, ripgrep
# and fd to search, lazygit in the colors of the theme, direnv for the environment of a project.
# eza and bat take the 16 colors of the terminal, which the theme engine sets. Whoever has an
# own lazygit config gets it as is.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  id = branding.id;

  # The settings of lazygit; the theme engine writes the colors beside them (lazygit.yml)
  lazygitBase = pkgs.writeText "lazygit.yml" (builtins.toJSON {
    disableStartupPopups = true;
    notARepository = "skip";
    promptToReturnFromSubprocess = false;
    update.method = "never";
    gui = {
      showListFooter = false;
      showRandomTip = false;
      showCommandLog = false;
      showBottomLine = false;
      nerdFontsVersion = "3";
    };
  });

  lazygit = pkgs.writeShellScriptBin "lazygit" ''
    own="''${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"
    if [ -z "''${LG_CONFIG_FILE:-}" ] && [ ! -e "$own" ]; then
      export LG_CONFIG_FILE=${lazygitBase}
      for dir in ''${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR/${id}/theme"} /run/${id}/theme; do
        if [ -r "$dir/lazygit.yml" ]; then
          LG_CONFIG_FILE="$LG_CONFIG_FILE,$dir/lazygit.yml"
          break
        fi
      done
    fi
    exec ${lib.getExe pkgs.lazygit} "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    eza
    bat
    ripgrep
    fd
    (lib.hiPrio lazygit)
    pkgs.lazygit
    git
    wget
    curl
    pciutils
    usbutils
    parted
  ];

  environment.shellAliases = {
    ls = "eza --icons=auto --group-directories-first";
    ll = "eza --icons=auto --group-directories-first --long --git";
    la = "eza --icons=auto --group-directories-first --long --git --all";
    tree = "eza --icons=auto --tree";
    lg = "lazygit";
    ff = "fastfetch";
  };

  # bat in the colors of the terminal, so it follows the theme; plain when piped
  environment.variables.BAT_THEME = "ansi";

  # The environment of a project when entering its folder (.envrc, `use flake`)
  programs.direnv = {
    enable = lib.mkDefault true;
    nix-direnv.enable = true;
    silent = true;
  };
}
