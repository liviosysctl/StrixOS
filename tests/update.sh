# The decisions of <id>-update with the theme repositories, with stand-ins for
# nix, the rebuild and the theme engine (eval.nix: update-tool).
#   bash tests/update.sh modules/tools/common.sh modules/tools/update.sh
set -euo pipefail

common=$1
update=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
# root without being root
printf '#!/bin/sh\necho 0\n' >"$work/bin/id"
# nix flake update changes the lock when NIX_CHANGES=1, fails when NIX_FAILS=1
cat >"$work/bin/nix" <<'EOF'
#!/bin/sh
echo nix >>"$LOG"
[ "${NIX_FAILS:-0}" = 1 ] && exit 1
[ "${NIX_CHANGES:-0}" = 1 ] && echo "new" >>"$DISTRO_CONFIG_DIR/flake.lock"
exit 0
EOF
cat >"$work/rebuild" <<'EOF'
#!/bin/sh
echo rebuild >>"$LOG"
exit "${REBUILD_EXIT:-0}"
EOF
# repos update: THEME_REV becomes the commit, THEME_PROBLEM a problem note,
# THEME_EXIT the exit code
cat >"$work/theme" <<'EOF'
#!/bin/sh
echo "theme $*" >>"$LOG"
[ -n "${THEME_REV:-}" ] && jq --arg r "$THEME_REV" '.repos[0].rev = $r' "$REPOS_FILE" >"$REPOS_FILE.new" && mv "$REPOS_FILE.new" "$REPOS_FILE"
[ -n "${THEME_PROBLEM:-}" ] && jq --arg p "$THEME_PROBLEM" '.repos[0].problem = $p' "$REPOS_FILE" >"$REPOS_FILE.new" && mv "$REPOS_FILE.new" "$REPOS_FILE"
exit "${THEME_EXIT:-0}"
EOF
chmod +x "$work/bin/"* "$work/rebuild" "$work/theme"
{
  echo 'set -euo pipefail'
  cat "$common" "$update"
} >"$work/update"

export PATH="$work/bin:$PATH" LOG="$work/log" LOCK_FILE="$work/lock" REBUILD="$work/rebuild"
export DEFAULT_CONFIG_DIR=/nonexistent DISTRO_CONFIG_DIR="$work/etc" THEME_COMMAND="$work/theme"

fails=0
# case NAME EXPECTED_EXIT EXPECTED_LOG [ARGS...], environment set by the caller
case_() {
  local name=$1 want=$2 want_log=$3
  shift 3
  rm -rf "$DISTRO_CONFIG_DIR" "$LOG"
  mkdir -p "$DISTRO_CONFIG_DIR"
  echo old >"$DISTRO_CONFIG_DIR/flake.lock"
  if [ "${REPOS:-1}" = 1 ]; then
    echo '{"version":1,"repos":[{"url":"https://x.org/a/b","rev":"aaa","themes":["t"]}]}' >"$DISTRO_CONFIG_DIR/themes.json"
  fi
  local got=0
  bash "$work/update" "$@" >"$work/out" 2>&1 || got=$?
  local log
  log=$(paste -sd ' ' "$LOG" 2>/dev/null || true)
  if [ "$got" = "$want" ] && [ "$log" = "$want_log" ]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s: exit %s (want %s), ran "%s" (want "%s")\n' "$name" "$got" "$want" "$log" "$want_log"
    sed 's/^/       /' "$work/out"
    fails=$((fails + 1))
  fi
}

REPOS=0 case_ "no repositories, nothing new" 0 "nix"
REPOS=0 NIX_CHANGES=1 case_ "no repositories, a new release" 0 "nix rebuild"
case_ "repositories, nothing new" 0 "theme repos update nix"
THEME_REV=bbb case_ "a theme repository moved: rebuild" 0 "theme repos update nix rebuild"
THEME_PROBLEM=x THEME_EXIT=1 case_ "only a problem note: no rebuild" 0 "theme repos update nix"
THEME_EXIT=1 NIX_CHANGES=1 case_ "a failing repository never stops the update" 0 "theme repos update nix rebuild"
NIX_CHANGES=1 REBUILD_EXIT=1 case_ "a failed rebuild keeps the old lock" 3 "theme repos update nix rebuild"
grep -qx old "$DISTRO_CONFIG_DIR/flake.lock" || { echo "FAIL the lock was not restored"; fails=$((fails + 1)); }
NIX_FAILS=1 case_ "no network" 5 "theme repos update nix"
case_ "--themes, nothing new" 0 "theme repos update" --themes
THEME_REV=bbb case_ "--themes, a new commit: rebuild without nix" 0 "theme repos update rebuild" --themes
THEME_REV=bbb case_ "--themes with a name" 0 "theme repos update Odd rebuild" --themes Odd
THEME_EXIT=1 case_ "--themes, the repository failed" 6 "theme repos update" --themes
REPOS=0 case_ "--themes without themes.json still asks the engine" 0 "theme repos update" --themes
case_ "a wrong argument" 64 "" --nope

if [ "$fails" -ne 0 ]; then
  echo "$fails update checks failed"
  exit 1
fi
echo "all update checks passed"
