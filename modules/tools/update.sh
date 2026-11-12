# <name>-update [--themes [REPO]]: fetch the new version of the distro and of
# every connected theme repository, and switch to it.
#   --themes [REPO]  only the theme repositories, or the one named (address or
#                    name), as "Update now" in Settings › Themes
# If the build fails, the old flake.lock stays, and with it the old version.
# A theme repository that fails keeps its commit and never stops the update.
usage() {
  echo "Usage: $(basename "$0") [--themes [REPO]]"
}

themes_only=false
only=""
case "${1:-}" in
  "") ;;
  --themes)
    themes_only=true
    only="${2:-}"
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

require_root
take_lock

lock="$config_dir/flake.lock"
repos="$config_dir/themes.json"

# The commits of the theme repositories, without the problem notes: only a new
# commit needs a rebuild.
pins() {
  if [ -e "$repos" ]; then
    jq -c '[.repos[]? | {url, rev, themes}]' "$repos" 2>/dev/null || echo broken
  fi
}

# Theme repositories first; their themes come with the same rebuild.
themes_changed=false
themes_failed=false
if [ -n "${THEME_COMMAND:-}" ] && { $themes_only || [ -e "$repos" ]; }; then
  before=$(pins)
  echo "Theme repositories:"
  if ! REPOS_FILE="$repos" "$THEME_COMMAND" repos update ${only:+"$only"}; then
    themes_failed=true
    echo "Not every theme repository could be updated, those keep their commit." >&2
  fi
  if [ "$(pins)" != "$before" ]; then
    themes_changed=true
  fi
elif $themes_only; then
  echo "Themes are switched off on this system." >&2
  exit 64
fi

if $themes_only; then
  if ! $themes_changed; then
    echo "The themes are already up to date."
    if $themes_failed; then exit 6; fi
    exit 0
  fi
  if ! "$REBUILD" switch; then
    echo "Rebuild failed, the new themes come with the next one." >&2
    exit 3
  fi
  if $themes_failed; then exit 6; fi
  exit 0
fi

# An interrupted run left flake.lock.prev behind: the state before it counts.
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

if cmp -s "$lock" "$lock.prev" && ! $themes_changed; then
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
