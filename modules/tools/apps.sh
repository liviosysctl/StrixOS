# <name>-apps add|remove|list [paket]
# Die Schnittstelle zum Store. Exit-Codes:
#   0 erledigt, 1 keine Rechte, 2 unbekanntes Paket, 3 Neubau fehlgeschlagen,
#   4 Sperre nicht bekommen, 64 falscher Aufruf
usage() {
  echo "Usage: $(basename "$0") add|remove <package> | list"
}

cmd="${1:-}"
attr="${2:-}"
file="$config_dir/apps.json"

case "$cmd" in
  list)
    # Liegt apps.json.prev da, läuft gerade ein Neubau oder einer wurde
    # abgebrochen. Installiert ist dann der Stand in .prev.
    if [ -e "$file.prev" ]; then
      jq -r '.packages[].attr' "$file.prev"
    else
      jq -r '.packages[].attr' "$file"
    fi
    exit 0
    ;;
  add | remove) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

# Nur Attributpfade wie "firefox" oder "kdePackages.kate". Verhindert auch,
# dass etwas anderes als ein Name in den nix-eval-Ausdruck gelangt.
if ! [[ "$attr" =~ ^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*$ ]]; then
  echo "Not a package name: '$attr'" >&2
  exit 2
fi

require_root
take_lock

# Ein abgebrochener Lauf (Strom weg, Ctrl+C) hat apps.json.prev hinterlassen:
# Dann gilt der Stand davor.
if [ -e "$file.prev" ]; then
  mv -f "$file.prev" "$file"
  echo "Restored $file from an interrupted run." >&2
fi

present=false
if jq -e --arg a "$attr" 'any(.packages[]; .attr == $a)' "$file" >/dev/null; then
  present=true
fi

unfree=""
if [ "$cmd" = add ]; then
  if $present; then
    echo "$attr is already installed."
    exit 0
  fi

  err=$(mktemp)
  trap 'rm -f "$err"' EXIT
  if ! info=$(nix eval --json "$config_dir#nixosConfigurations.$CONFIG_ATTR.pkgs.$attr" \
    --apply 'p: if (p.type or "") == "derivation"
                then { unfree = p.meta.unfree or false; pname = p.pname or (builtins.parseDrvName p.name).name; }
                else throw "not a package"' 2>"$err"); then
    echo "Unknown package: $attr" >&2
    tail -n 3 "$err" >&2
    exit 2
  fi
  unfree=$(jq -r 'if .unfree then .pname else "" end' <<<"$info")
  # shellcheck disable=SC2016 # $a und $u sind jq-Variablen, keine Shell-Variablen
  filter='.packages += [ {attr: $a} + (if $u == "" then {} else {unfree: $u} end) ]'
else
  if ! $present; then
    echo "$attr is not installed."
    exit 0
  fi
  # shellcheck disable=SC2016
  filter='.packages |= map(select(.attr != $a))'
fi

# Erst neben die alte Datei schreiben, dann umbenennen: nie eine halbe apps.json.
cp -p "$file" "$file.prev"
trap 'mv -f "$file.prev" "$file"; exit 130' INT TERM
jq --arg a "$attr" --arg u "$unfree" "$filter" "$file" >"$file.new"
chmod 0644 "$file.new"
mv -f "$file.new" "$file"

if ! "$REBUILD" switch; then
  mv -f "$file.prev" "$file"
  echo "Build failed, $file is back to its previous state." >&2
  exit 3
fi

rm -f "$file.prev"
