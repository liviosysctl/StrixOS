# Tab completion for @command@ in fish. modules/theme.nix fills in the name.

complete -c @command@ -f

complete -c @command@ -n __fish_use_subcommand -a list -d 'Themes and their variants'
complete -c @command@ -n __fish_use_subcommand -a current -d 'The current theme'
complete -c @command@ -n __fish_use_subcommand -a show -d 'Colors of a theme as JSON'
complete -c @command@ -n __fish_use_subcommand -a status -d 'Whether every part shows the current theme'
complete -c @command@ -n __fish_use_subcommand -a set -d 'Switch the theme (needs root)'
complete -c @command@ -n __fish_use_subcommand -a apply -d 'Apply the stored theme again (needs root)'
complete -c @command@ -n __fish_use_subcommand -a help -d 'Usage'

# One theme after set and show. `list --names` already prints name<TAB>description.
complete -c @command@ -n '__fish_seen_subcommand_from set show; and test (count (commandline -opc)) -eq 2' -a '(@command@ list --names 2>/dev/null)'
