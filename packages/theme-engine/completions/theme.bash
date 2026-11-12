# Tab completion for @command@ in bash. modules/theme.nix fills in the name.
# Commands first, then for set and show the themes from `@command@ list --names`,
# and the sub-commands of repos.
# Works with sudo too: bash-completion hands `sudo @command@ ...` over to this.

_@function@() {
  # Split what is typed up to the cursor at spaces only. COMP_WORDS would
  # also split at ':' and break up "janus:dark".
  local line=${COMP_LINE:0:COMP_POINT}
  local -a words
  read -ra words <<<"$line"
  [[ $line == *[[:space:]] ]] && words+=("")
  local count=${#words[@]}
  local current=${words[count - 1]}
  COMPREPLY=()

  if ((count == 2)); then
    mapfile -t COMPREPLY < <(compgen -W "list current show status set apply repos help" -- "$current")
  elif ((count == 3)) && [[ ${words[1]} == repos ]]; then
    mapfile -t COMPREPLY < <(compgen -W "list add remove update check" -- "$current")
  elif ((count == 3)) && [[ ${words[1]} == set || ${words[1]} == show ]]; then
    local names
    names=$(@command@ list --names 2>/dev/null | cut -f1)
    mapfile -t COMPREPLY < <(compgen -W "$names" -- "$current")
    # bash replaces only the part after the last ':' of the word, so the
    # candidates lose what is already typed up to there
    if [[ $current == *:* && $COMP_WORDBREAKS == *:* ]]; then
      local prefix=${current%"${current##*:}"}
      local i
      for i in "${!COMPREPLY[@]}"; do
        COMPREPLY[i]=${COMPREPLY[i]#"$prefix"}
      done
    fi
  fi
}

complete -F _@function@ @command@
