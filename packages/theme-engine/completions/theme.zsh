#compdef @command@
# Tab completion for @command@ in zsh. modules/theme.nix fills in the name.

local -a commands
commands=(
  'list:themes and their variants'
  'current:the current theme'
  'show:colors of a theme as JSON'
  'status:whether every part shows the current theme'
  'set:switch the theme (needs root)'
  'apply:apply the stored theme again (needs root)'
  'help:usage'
)

if (( CURRENT == 2 )); then
  _describe -t commands 'command' commands
elif (( CURRENT == 3 )) && [[ $words[2] == (set|show) ]]; then
  local -a names descriptions
  local line
  for line in ${(f)"$(@command@ list --names 2>/dev/null)"}; do
    names+=("${line%%$'\t'*}")
    descriptions+=("${line%%$'\t'*}  ${line#*$'\t'}")
  done
  compadd -l -d descriptions -- $names
fi
