# The commands of the desktop in Rust: screenshots and recordings, what happens when nobody is at
# the machine, the system monitor, default apps, storage, printers and drives that are plugged in.
# One program; `command` installs it under the name of one of its commands, <id>-capture,
# <id>-automount and so on, with the programs that command starts in its PATH. The crate has a
# neutral name: the program reads the distribution's id from the name it is started by. The unit
# tests run while building.
{
  lib,
  rustPlatform,
  makeWrapper,
  runCommand,
  pkg-config,
  dbus,
}:

let
  branding = import ../../branding.nix;
  cargo = lib.importTOML ./Cargo.toml;

  desk = rustPlatform.buildRustPackage {
    pname = "desk";
    inherit (cargo.package) version;

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./Cargo.toml
        ./Cargo.lock
        ./src
      ];
    };
    cargoLock.lockFile = ./Cargo.lock;

    # <id>-automount talks to udisks2 on the system bus (libdbus)
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ dbus ];

    meta = {
      inherit (cargo.package) description;
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "desk";
    };
  };
in
desk
// {
  # <id>-<name>, with `inputs` in its PATH
  command =
    name: inputs:
    runCommand "${branding.id}-${name}"
      {
        nativeBuildInputs = [ makeWrapper ];
        meta.mainProgram = "${branding.id}-${name}";
      }
      ''
        # The program reads its command and the distribution's id from its name
        makeWrapper ${lib.getExe desk} $out/bin/${branding.id}-${name} \
          --inherit-argv0 \
          --prefix PATH : ${lib.makeBinPath inputs}
      '';
}
