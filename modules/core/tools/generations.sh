# <name>-generations [list|switch N|clean]: the versions of the system that are still installed.
# Every update and every rebuild leaves the version before it; the boot menu starts them too.
#   list      all of them as JSON, for Settings › Versions (no root needed)
#   switch N  go back (or forward) to generation N, now and for the next start
#   clean     keep the last five and free the space of the rest
usage() {
  echo "Usage: $(basename "$0") [list|switch N|clean]"
}

profile=/nix/var/nix/profiles/system

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
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
