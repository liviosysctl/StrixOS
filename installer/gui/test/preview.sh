#!/usr/bin/env bash
# Renders every page of the graphical installer to PNG against a mock back end.
#
#     installer/gui/test/preview.sh STRIXUI_QML_DIR OUT_DIR
#
# STRIXUI_QML_DIR holds the Strix module (design-system/qml of StrixUI). Needs the qml tool of Qt 6
# (nix shell nixpkgs#qt6.qtdeclarative). Fails on any QML warning, so a broken binding shows up
# here before the ISO is built.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
qml_dir=$(realpath "$1")
out=$(realpath -m "$2")
mkdir -p "$out"

# The window's folder as the package builds it: the QML, Texts.js and the test's own files
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$here"/../qml/*.qml "$here"/*.qml "$work"/
rm "$work/shell.qml"
{
  echo '.pragma library'
  printf 'var all = '
  cat "$here/../texts.json"
  echo ';'
} >"$work/Texts.js"
printf '.pragma library\nvar dir = "%s";\n' "$out" >"$work/Out.js"

log=$work/log
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH=$qml_dir${QML_IMPORT_PATH:+:$QML_IMPORT_PATH} qml "$work/Preview.qml" 2>&1 | tee "$log"
if grep -v '^qml: ok ' "$log" | grep -q .; then
  echo "QML warnings, see above" >&2
  exit 1
fi
