# <name>-update [--themes [REPO]]: fetch the new version of the distro and of
# every connected theme repository, and switch to it.
#   --themes [REPO]  only the theme repositories, or the one named (address or
#                    name), as "Update now" in Settings › Themes
# If the build fails, the old flake.lock stays, and with it the old version. The same when the
# desktop does not come up with the new version: the system goes back by itself (exit 7).
# At the end it says whether there is new firmware (fwupd).
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

# New firmware for the machine and its devices (fwupd) is only announced: installing it wants
# a restart, which is the person's to decide.
firmware() {
  [ -n "${FWUPDMGR:-}" ] || return 0
  "$FWUPDMGR" refresh >/dev/null 2>&1 || return 0
  if "$FWUPDMGR" get-updates >/dev/null 2>&1; then
    echo "New firmware is available: fwupdmgr update installs it."
  fi
}

# What the shell of USER (with the id UID) says to "is the screen locked": true, false, or nothing
# when it does not run or does not work
shell_says() {
  runuser -u "$1" -- env XDG_RUNTIME_DIR="/run/user/$2" \
    "$SHELL_QS" -c "$SHELL_CONFIG" ipc call lock locked 2>/dev/null || true
}

# The desktop must come up with the new version. For everyone at the desktop the shell is started
# again, which also shows the new version at once, and has to answer within 20 seconds. A locked
# screen is left alone: its lock cannot be started again under it.
restarted=()
shell_works() {
  [ -n "${SHELL_UNIT:-}" ] || return 0
  local uid user answer
  while read -r uid user _; do
    [ "$(shell_says "$user" "$uid")" = false ] || continue
    restarted+=("$user")
    systemctl --machine="$user@.host" --user restart "$SHELL_UNIT" || return 1
    answer=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 2
      answer=$(shell_says "$user" "$uid")
      [ -z "$answer" ] || break
    done
    [ -n "$answer" ] || return 1
  done < <(loginctl list-users --no-legend)
}

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
  firmware
  exit 0
fi

if ! "$REBUILD" switch; then
  mv -f "$lock.prev" "$lock"
  echo "Update failed, the previous version stays active." >&2
  exit 3
fi

if ! shell_works; then
  echo "The desktop does not come up with the new version: going back to the previous one." >&2
  mv -f "$lock.prev" "$lock"
  "$REBUILD" switch --rollback || echo "Could not go back. Start the previous version from the boot menu." >&2
  for user in "${restarted[@]}"; do
    systemctl --machine="$user@.host" --user restart "$SHELL_UNIT" || true
  done
  exit 7
fi

rm -f "$lock.prev"
firmware
