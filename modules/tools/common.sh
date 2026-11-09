# Gemeinsamer Anfang aller Werkzeuge (rebuild, update, apps).
# DEFAULT_CONFIG_DIR, CONFIG_ATTR und LOCK_FILE kommen aus runtimeEnv.

# DISTRO_CONFIG_DIR nur für Tests, normal ist es immer /etc/nixos.
config_dir="${DISTRO_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo (or pkexec)." >&2
    exit 1
  fi
}

# Nur ein Neubau gleichzeitig. Wer die Sperre schon hält (update und apps
# rufen rebuild auf), gibt das über DISTRO_LOCK_HELD weiter.
take_lock() {
  if [ -n "${DISTRO_LOCK_HELD:-}" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  if ! flock --nonblock 9; then
    echo "Waiting for another rebuild to finish..." >&2
    if ! flock --wait 1800 9; then
      echo "Gave up after 30 minutes of waiting for the other rebuild." >&2
      exit 4
    fi
  fi
  export DISTRO_LOCK_HELD=1
}
