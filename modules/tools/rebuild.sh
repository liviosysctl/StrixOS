# <name>-rebuild [switch|boot|test|build|dry-build] [more nixos-rebuild options]
usage() {
  echo "Usage: $(basename "$0") [switch|boot|test|build|dry-build] [nixos-rebuild options]"
}

mode="${1:-switch}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$mode" in
  switch | boot | test | build | dry-build) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    usage >&2
    exit 64
    ;;
esac

require_root
take_lock

# exec keeps the lock (file descriptor 9) until nixos-rebuild is done.
exec nixos-rebuild "$mode" --flake "$config_dir#$CONFIG_ATTR" "$@"
