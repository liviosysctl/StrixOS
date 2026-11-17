# <name>-shell [--proprietary] <package>...
# A shell with the packages from the nixpkgs of this system, as nix-shell -p does: nothing is
# installed, apps.json stays as it is, and after exit the packages are gone again (until the
# next garbage collection they stay in the store, so a second time is quick).
usage() {
  echo "Usage: $(basename "$0") [--proprietary] <package>..."
}

proprietary=false
packages=()
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    --proprietary) proprietary=true ;;
    *)
      # Only attribute paths like "gimp" or "kdePackages.kate", as in <name>-apps
      if ! [[ "$arg" =~ ^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*$ ]]; then
        echo "Not a package name: '$arg'" >&2
        exit 2
      fi
      packages+=("nixpkgs#$arg")
      ;;
  esac
done
if [ "${#packages[@]}" -eq 0 ]; then
  usage >&2
  exit 64
fi

flags=()
if $proprietary; then
  # nixpkgs refuses unfree packages unless the environment allows them
  export NIXPKGS_ALLOW_UNFREE=1
  flags+=(--impure)
fi

echo "A shell with ${packages[*]#nixpkgs#}. Nothing is installed; exit leaves it."
exec nix shell "${flags[@]}" "${packages[@]}"
