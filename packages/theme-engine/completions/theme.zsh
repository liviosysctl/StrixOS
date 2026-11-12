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
  'repos:theme repositories'
  'help:usage'
)

local -a repos
repos=(
  'list:connected theme repositories'
  'add:fetch, check and connect a repository (needs root)'
  'remove:disconnect a repository (needs root)'
  'update:take the newest commit that passes (needs root)'
  'check:check a checkout against layout 1'
)

if (( CURRENT == 2 )); then
  _describe -t commands 'command' commands
elif (( CURRENT == 3 )) && [[ $words[2] == repos ]]; then
  _describe -t repos 'repos command' repos
elif (( CURRENT == 4 )) && [[ $words[2] == repos && $words[3] == check ]]; then
  _files -/
elif (( CURRENT == 3 )) && [[ $words[2] == (set|show) ]]; then
  local -a names descriptions
  local line
  for line in ${(f)"$(@command@ list --names 2>/dev/null)"}; do
    names+=("${line%%$'\t'*}")
    descriptions+=("${line%%$'\t'*}  ${line#*$'\t'}")
  done
  compadd -l -d descriptions -- $names
fi
