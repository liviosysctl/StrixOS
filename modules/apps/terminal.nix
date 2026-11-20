# The terminal, set up for every user: zsh with suggestions and colors, eza and bat in place of plain listings, ripgrep
# and fd to search, lazygit in the colors of the theme, direnv for the environment of a project.
# eza and bat take the 16 colors of the terminal, which the theme engine sets; folders in
# listings and the marks of fzf take the accent (shell.sh of the theme engine). Whoever has an
# own lazygit config gets it as is.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  id = branding.id;

  # The settings of lazygit; the theme engine writes the colors beside them (lazygit.yml)
  lazygitBase = pkgs.writeText "lazygit.yml" (
    builtins.toJSON {
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
    }
  );

  # Reads shell.sh of the session's theme, else of the machine's
  colors = ''
    local dir
    for dir in ''${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR/${id}/theme"} /run/${id}/theme; do
      if [[ -r "$dir/shell.sh" ]]; then source "$dir/shell.sh"; break; fi
    done
  '';

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
    fzf
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

  # zsh is the shell of every user: suggestions from the history while typing, commands colored
  # as they are typed, a menu on Tab. The colors are the terminal's, so they follow the theme.
  users.defaultUserShell = pkgs.zsh;
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 10000;
    setOptions = [
      "HIST_IGNORE_ALL_DUPS"
      "HIST_IGNORE_SPACE"
      "SHARE_HISTORY"
      "AUTO_CD"
      "INTERACTIVE_COMMENTS"
    ];
    # No questions at the first start of a user without a .zshrc
    shellInit = "zsh-newuser-install() { :; }";
    interactiveShellInit = ''
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      bindkey -e
      # Up and Down look through the history for what is already typed
      autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey '^[[A' up-line-or-beginning-search
      bindkey '^[[B' down-line-or-beginning-search
      bindkey '^[[1;5C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^[[H' beginning-of-line
      bindkey '^[[F' end-of-line
      bindkey '^[[3~' delete-char
      # The colors of the theme for eza, ls and fzf (shell.sh of the theme engine), before every
      # prompt, so a change of theme shows at once
      ${id}_colors() { ${colors} }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd ${id}_colors
    '';
  };

  # Ctrl R looks through the history with fzf, Ctrl T through the files, ** Tab completes
  programs.fzf = {
    keybindings = true;
    fuzzyCompletion = true;
  };

  programs.bash.interactiveShellInit = ''
    ${id}_colors() { ${colors} }
    PROMPT_COMMAND="${id}_colors''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  '';

  # bat in the colors of the terminal, so it follows the theme; plain when piped
  environment.variables.BAT_THEME = "ansi";

  # The environment of a project when entering its folder (.envrc, `use flake`)
  programs.direnv = {
    enable = lib.mkDefault true;
    nix-direnv.enable = true;
    silent = true;
  };
}
