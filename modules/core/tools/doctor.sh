# <name>-doctor [--report]: looks the system over and says what is wrong, in words.
#   (nothing)  the checks, one line each: ok, look (worth a look) or fail
#   --report   the checks and the logs of this start in one archive in the home folder, to send
#              along with a question; it says what is in it
# Needs no root. Exit 1 when a check failed.
# A check that cannot be made (no systemd, no network) must not end the others.
usage() {
  echo "Usage: $(basename "$0") [--report]"
}

case "${1:-}" in
  "" | --report) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

failed=0
ok() { printf '  ok    %s\n' "$1"; }
look() { printf '  look  %s\n        %s\n' "$1" "$2"; }
fail() {
  printf '  fail  %s\n        %s\n' "$1" "$2"
  failed=$((failed + 1))
}

checks() {
  echo "The system"
  units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  if [ -z "$units" ]; then ok "Every service of the system runs"; else fail "Services of the system failed: $units" "systemctl status <name> says why"; fi

  for mount in / /nix /home; do
    used=$(df --output=pcent "$mount" 2>/dev/null | tail -n 1 | tr -dc '0-9' || true)
    [ -n "$used" ] || continue
    if [ "$used" -ge 95 ]; then
      fail "$mount is $used % full" "sudo $ID-generations clean frees the space of old versions"
    elif [ "$used" -ge 85 ]; then
      look "$mount is $used % full" "sudo $ID-generations clean frees the space of old versions"
    else
      ok "$mount has room ($used % used)"
    fi
  done

  errors=$(journalctl --boot --priority=err --quiet --no-pager 2>/dev/null | wc -l || true)
  if [ "$errors" -gt 50 ]; then look "$errors errors in the log since the start" "journalctl -b -p err shows them"; else ok "The log of this start is quiet ($errors errors)"; fi

  echo "Updates"
  lock="$config_dir/flake.lock"
  if [ -r "$lock" ]; then
    read -r owner repo ref rev < <(jq -r --arg id "$CONFIG_ATTR" '.nodes[.nodes.root.inputs[$id]]
      | [.original.owner, .original.repo, (.original.ref // "HEAD"), .locked.rev] | join(" ")' "$lock")
    target="refs/heads/$ref"
    [ "$ref" != HEAD ] || target=HEAD
    newest=$(git ls-remote "https://github.com/$owner/$repo" "$target" 2>/dev/null | cut -f 1 || true)
    if [ -z "$newest" ]; then
      look "GitHub does not answer" "Without the network there are no updates"
    elif [ "$newest" = "$rev" ]; then
      ok "The newest version of $ref is installed"
    else
      look "A newer version of $ref is there" "sudo $ID-update installs it"
    fi
  else
    fail "$lock is missing" "The machine's configuration is not where the tools look for it"
  fi
  for cache in "https://cache.nixos.org" "https://$ID.cachix.org"; do
    if curl --fail --silent --max-time 8 "$cache/nix-cache-info" >/dev/null; then
      ok "$cache answers"
    else
      look "$cache does not answer" "An update would build everything on this machine"
    fi
  done

  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo "The desktop"
    if systemctl --user is-active --quiet "$ID-shell.service"; then ok "The shell runs"; else fail "The shell does not run" "systemctl --user restart $ID-shell starts it; journalctl --user -u $ID-shell says why it stopped"; fi
    units=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
    if [ -z "$units" ]; then ok "Every service of the session runs"; else fail "Services of the session failed: $units" "systemctl --user status <name> says why"; fi
    mistakes=$(hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d' || true)
    if [ -z "$mistakes" ]; then ok "Hyprland read its configuration without a mistake"; else fail "Hyprland found mistakes in its configuration" "$mistakes"; fi
    if systemctl --user is-active --quiet xdg-desktop-portal.service; then ok "The portal for file choosers and screen sharing runs"; else look "The portal does not run" "Choosing a file and sharing the screen need it: systemctl --user restart xdg-desktop-portal"; fi
    if wpctl status >/dev/null 2>&1; then ok "Sound (PipeWire) answers"; else fail "Sound (PipeWire) does not answer" "systemctl --user restart pipewire wireplumber"; fi
  fi
}

if [ "${1:-}" != --report ]; then
  checks
  echo
  if [ "$failed" -eq 0 ]; then echo "Nothing failed."; else echo "$failed failed."; fi
  [ "$failed" -eq 0 ]
  exit
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
name="$ID-report-$(date +%Y-%m-%d_%H-%M)"
mkdir "$work/$name"
checks >"$work/$name/checks.txt" 2>&1 || true
nixos-version >"$work/$name/version.txt" 2>&1 || true
cp "$config_dir/flake.lock" "$work/$name/" 2>/dev/null || true
journalctl --boot --no-pager >"$work/$name/log-system.txt" 2>&1 || true
journalctl --user --boot --no-pager >"$work/$name/log-session.txt" 2>&1 || true
hyprctl systeminfo >"$work/$name/hyprland.txt" 2>&1 || true
tar -C "$work" -czf "$HOME/$name.tar.gz" "$name"
cat "$work/$name/checks.txt"
echo
echo "The report is $HOME/$name.tar.gz: these checks, the version, flake.lock, the logs of the"
echo "system and of the session since the start, and what Hyprland knows about the machine."
echo "Logs can hold names of networks, devices and files: look through them before you send it."
