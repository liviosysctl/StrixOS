# Tab completion for @command@ in fish. modules/theme.nix fills in the name.

complete -c @command@ -f

complete -c @command@ -n __fish_use_subcommand -a list -d 'Themes and their variants'
complete -c @command@ -n __fish_use_subcommand -a current -d 'The current theme'
complete -c @command@ -n __fish_use_subcommand -a show -d 'Colors of a theme as JSON'
complete -c @command@ -n __fish_use_subcommand -a status -d 'Whether every part shows the current theme'
complete -c @command@ -n __fish_use_subcommand -a set -d 'Switch the theme (needs root)'
complete -c @command@ -n __fish_use_subcommand -a apply -d 'Apply the stored theme again (needs root)'
complete -c @command@ -n __fish_use_subcommand -a repos -d 'Theme repositories'
complete -c @command@ -n __fish_use_subcommand -a help -d 'Usage'

# The sub-commands of repos
set -l repos_condition '__fish_seen_subcommand_from repos; and test (count (commandline -opc)) -eq 2'
complete -c @command@ -n $repos_condition -a list -d 'Connected theme repositories'
complete -c @command@ -n $repos_condition -a add -d 'Fetch, check and connect a repository (needs root)'
complete -c @command@ -n $repos_condition -a remove -d 'Disconnect a repository (needs root)'
complete -c @command@ -n $repos_condition -a update -d 'Take the newest commit that passes (needs root)'
complete -c @command@ -n $repos_condition -a check -d 'Check a checkout against layout 1'

# One theme after set and show. `list --names` already prints name<TAB>description.
complete -c @command@ -n '__fish_seen_subcommand_from set show; and test (count (commandline -opc)) -eq 2' -a '(@command@ list --names 2>/dev/null)'
