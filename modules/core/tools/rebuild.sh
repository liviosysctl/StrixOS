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

# When someone watches: the build with a tree of what is built and fetched (nix-output-monitor),
# then what changes against the running system, package by package (dix). nixos-rebuild finds
# the system built and only has to switch to it. With more options (--rollback, --show-trace)
# and without a terminal it runs as it always did.
case "$mode" in
  switch | boot | test)
    if [ "$#" -eq 0 ] && [ -t 2 ]; then
      built=$(mktemp -d)
      trap 'rm -rf "$built"' EXIT
      nix build "$config_dir#nixosConfigurations.$CONFIG_ATTR.config.system.build.toplevel" \
        --out-link "$built/system" --log-format internal-json --verbose |& nom --json
      if [ -e /run/current-system ]; then
        if [ "$(readlink -f /run/current-system)" = "$(readlink -f "$built/system")" ]; then
          echo "Nothing changes: this is the system that is running."
        else
          dix diff /run/current-system "$built/system" || true
        fi
      fi
      rm -rf "$built"
      trap - EXIT
    fi
    ;;
esac

# exec keeps the lock (file descriptor 9) until nixos-rebuild is done.
exec nixos-rebuild "$mode" --flake "$config_dir#$CONFIG_ATTR" "$@"
