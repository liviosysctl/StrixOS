# The Store, installed as <id>-store (e.g. strix-store). The crate has a neutral name; only the
# installed program carries the distro's. The unit tests run while building.
{ lib, rustPlatform }:

let
  branding = import ../../branding.nix;
  cargo = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage {
  pname = "${branding.id}-store";
  inherit (cargo.package) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./fixtures
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  postInstall = ''
    mv $out/bin/store $out/bin/${branding.id}-store
  '';

  meta = {
    description = cargo.package.description;
    mainProgram = "${branding.id}-store";
    platforms = lib.platforms.linux;
  };
}
