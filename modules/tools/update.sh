# <name>-update: neue Version der Distro holen und aktivieren.
# Schlägt der Neubau fehl, bleibt die alte flake.lock und damit die alte Version.
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: $(basename "$0")"
  exit 0
fi

require_root
take_lock

lock="$config_dir/flake.lock"

# Ein abgebrochener Lauf hat flake.lock.prev hinterlassen: Dann gilt der Stand davor.
if [ -e "$lock.prev" ]; then
  mv -f "$lock.prev" "$lock"
  echo "Restored $lock from an interrupted update." >&2
fi

cp -p "$lock" "$lock.prev"
trap 'mv -f "$lock.prev" "$lock"; exit 130' INT TERM

if ! nix flake update --flake "$config_dir"; then
  mv -f "$lock.prev" "$lock"
  echo "Could not fetch the update. Check the network." >&2
  exit 5
fi

if cmp -s "$lock" "$lock.prev"; then
  rm -f "$lock.prev"
  echo "Already up to date."
  exit 0
fi

if ! "$REBUILD" switch; then
  mv -f "$lock.prev" "$lock"
  echo "Update failed, the previous version stays active." >&2
  exit 3
fi

rm -f "$lock.prev"
