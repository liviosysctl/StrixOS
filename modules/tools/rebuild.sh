# <name>-rebuild [switch|boot|test|build|dry-build] [weitere nixos-rebuild-Optionen]
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

# exec behält die Sperre (Dateideskriptor 9) bis nixos-rebuild fertig ist.
exec nixos-rebuild "$mode" --flake "$config_dir#$CONFIG_ATTR" "$@"
