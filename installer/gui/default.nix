# The window of the graphical installer (qml/) as a Quickshell config, with its texts (texts.json)
# as Texts.js. The back end is the installer itself (`<id>-install --serve`, iso/live.nix), so the
# window and an automated install go through the same core.
{ runCommand }:

let
  branding = import ../../branding.nix;
in
runCommand "${branding.id}-installer-window" { } ''
  mkdir -p $out/share/${branding.id}-installer
  cp -r ${./qml} $out/share/${branding.id}-installer/qml
  chmod u+w $out/share/${branding.id}-installer/qml
  {
    echo '.pragma library'
    printf 'var all = '
    cat ${./texts.json}
    echo ';'
  } > $out/share/${branding.id}-installer/qml/Texts.js
''
