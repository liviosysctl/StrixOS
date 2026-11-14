# The graphical installer of the live session: the back end (backend.py) as
# <id>-installer-backend, and the window (qml/) as a Quickshell config. The
# back end runs the console installer's core (`<id>-install --core`), so both
# installers install the same way.
{
  lib,
  runCommand,
  makeWrapper,
  python3,
  networkmanager,
  systemd,
  # The console installer (installer/package.nix)
  installer,
}:

let
  branding = import ../../branding.nix;
in
runCommand "${branding.id}-installer-gui"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "${branding.id}-installer-backend";
    passthru.qml = ./qml;
  }
  ''
    install -D -m 0644 ${./backend.py} $out/share/${branding.id}-installer/backend.py
    makeWrapper ${lib.getExe python3} $out/bin/${branding.id}-installer-backend \
      --add-flags $out/share/${branding.id}-installer/backend.py \
      --set INSTALL_COMMAND ${lib.getExe installer} \
      --set NMCLI ${networkmanager}/bin/nmcli \
      --prefix PATH : ${lib.makeBinPath [ systemd ]}
    cp -r ${./qml} $out/share/${branding.id}-installer/qml
    chmod u+w $out/share/${branding.id}-installer/qml
    {
      echo '.pragma library'
      printf 'var all = '
      ${lib.getExe installer} --texts
      echo ';'
    } > $out/share/${branding.id}-installer/qml/Texts.js
  ''
