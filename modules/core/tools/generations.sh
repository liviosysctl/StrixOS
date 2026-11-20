# <name>-generations [list|switch N|clean|diff [N]]: the versions of the system that are still installed.
# Every update and every rebuild leaves the version before it; the boot menu starts them too.
#   list      all of them as JSON, for Settings › Versions (no root needed)
#   switch N  go back (or forward) to generation N, now and for the next start
#   clean     keep the last five and free the space of the rest
#   diff [N]  what generation N changed against the one before it, package by package; without
#             N, the running one. --json gives it to Settings (no root needed)
usage() {
  echo "Usage: $(basename "$0") [list|switch N|clean|diff [N] [--json]]"
}

profile=/nix/var/nix/profiles/system

# The number of a generation from its link (system-42-link)
number_of() {
  local link=${1##*/}
  link=${link#system-}
  echo "${link%-link}"
}

case "${1:-list}" in
  list)
    exec nixos-rebuild list-generations --json
    ;;
  switch)
    number="${2:-}"
    case "$number" in
      "" | *[!0-9]*)
        usage >&2
        exit 64
        ;;
    esac
    require_root
    take_lock
    if [ ! -e "$profile-$number-link" ]; then
      echo "There is no generation $number." >&2
      exit 2
    fi
    nix-env --profile "$profile" --switch-generation "$number"
    exec "$profile/bin/switch-to-configuration" switch
    ;;
  clean)
    require_root
    take_lock
    nix-env --profile "$profile" --delete-generations +5
    nix-collect-garbage
    # The boot menu lists the generations: write it again without the ones that went
    exec "$profile/bin/switch-to-configuration" boot
    ;;
  diff)
    shift
    format=human
    number=
    for arg in "$@"; do
      case "$arg" in
        --json) format=json ;;
        "" | *[!0-9]*)
          usage >&2
          exit 64
          ;;
        *) number=$arg ;;
      esac
    done
    [ -n "$number" ] || number=$(number_of "$(readlink "$profile")")
    if [ ! -e "$profile-$number-link" ]; then
      echo "There is no generation $number." >&2
      exit 2
    fi
    before=
    for link in "$profile"-*-link; do
      other=$(number_of "$link")
      if [ "$other" -lt "$number" ] && [ "$other" -gt "${before:-0}" ]; then
        before=$other
      fi
    done
    if [ -z "$before" ]; then
      if [ "$format" = json ]; then echo '{}'; else echo "Generation $number is the oldest still installed."; fi
      exit 0
    fi
    exec dix diff --output="$format" "$profile-$before-link" "$profile-$number-link"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
