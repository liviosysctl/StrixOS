# Tab completion of the theme command in bash, zsh and fish.
# Usage: bash completion.sh <package of the command> <command name>
# The command reads the themes in the repository; nothing is stored, so the
# default theme is current.
set -euo pipefail

package=$1
name=$2
export PATH="$package/bin:$PATH"
failed=0

check() {
  local shell=$1 line=$2 expected=$3 got=$4
  if [ "$got" == "$expected" ]; then
    printf 'ok   %-5s %-30s -> %s\n' "$shell" "\"$line\"" "$got"
  else
    printf 'FAIL %-5s %-30s -> %s, expected %s\n' "$shell" "\"$line\"" "$got" "$expected"
    failed=1
  fi
}

# bash: call the completion function as bash would, with the default word breaks
# shellcheck source=/dev/null
source "$package/share/bash-completion/completions/$name"
function=_${name//-/_}
bash_complete() {
  COMP_LINE=$1
  COMP_POINT=${#1}
  COMP_WORDBREAKS=$' \t\n"\'><=;|&(:'
  COMPREPLY=()
  "$function"
  printf '%s\n' "${COMPREPLY[@]}" | sort | paste -sd ' '
}

# zsh: the completion file with compadd and _describe standing in for the
# completion system, printing the names they get
zsh_complete() {
  local position=$1
  shift
  zsh -f -c '
    compadd() { while [[ $1 != -- ]]; do shift; done; shift; print -l -- "$@" }
    _describe() { local -a items; items=("${(@P)4}"); print -l -- "${items[@]%%:*}" }
    run() { source "$1" }
    file=$1; CURRENT=$2; shift 2; words=("$@")
    run "$file"
  ' zsh "$package/share/zsh/site-functions/_$name" "$position" "$@" | sort | paste -sd ' '
}

# fish: ask fish itself which completions it offers
fish_complete() {
  fish --no-config -c "
    set fish_complete_path $package/share/fish/vendor_completions.d \$fish_complete_path
    complete -C '$1'
  " | cut -f1 | sort | paste -sd ' '
}

commands="apply current help list set show status"
all="chamber chamber:dark chamber:light neutral neutral:dark"

check bash "$name " "$commands" "$(bash_complete "$name ")"
check bash "$name s" "set show status" "$(bash_complete "$name s")"
check bash "$name set " "$all" "$(bash_complete "$name set ")"
check bash "$name set ch" "chamber chamber:dark chamber:light" "$(bash_complete "$name set ch")"
# bash replaces only the part after ':', so only that part comes back
check bash "$name set chamber:" "dark light" "$(bash_complete "$name set chamber:")"
check bash "$name set chamber:d" "dark" "$(bash_complete "$name set chamber:d")"
check bash "$name show neu" "neutral neutral:dark" "$(bash_complete "$name show neu")"
check bash "$name list " "" "$(bash_complete "$name list ")"
check bash "$name set neutral " "" "$(bash_complete "$name set neutral ")"

check zsh "$name <2>" "$commands" "$(zsh_complete 2 "$name" "")"
check zsh "$name set <3>" "$all" "$(zsh_complete 3 "$name" set "")"
check zsh "$name show <3>" "$all" "$(zsh_complete 3 "$name" show "")"
check zsh "$name list <3>" "" "$(zsh_complete 3 "$name" list "")"

check fish "$name " "$commands" "$(fish_complete "$name ")"
check fish "$name set ch" "chamber chamber:dark chamber:light" "$(fish_complete "$name set ch")"
check fish "$name set chamber:" "chamber:dark chamber:light" "$(fish_complete "$name set chamber:")"
check fish "$name show " "$all" "$(fish_complete "$name show ")"
check fish "$name set neutral " "" "$(fish_complete "$name set neutral ")"

zsh -n "$package/share/zsh/site-functions/_$name"
fish --no-config -n "$package/share/fish/vendor_completions.d/$name.fish"
bash -n "$package/share/bash-completion/completions/$name"

if [ "$failed" -ne 0 ]; then
  echo "completion checks failed"
  exit 1
fi
echo "all completion checks passed"
