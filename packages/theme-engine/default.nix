# The theme engine, installed as <id>-theme (e.g. strix-theme).
# The crate has a neutral name; only the installed program carries the distro's.
# The unit tests run while building.
{ lib, rustPlatform, git }:

let
  branding = import ../../branding.nix;
  cargo = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage {
  pname = "${branding.id}-theme";
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

  # The tests of the theme repositories clone local Git repositories
  nativeCheckInputs = [ git ];

  postInstall = ''
    mv $out/bin/theme $out/bin/${branding.id}-theme
  '';

  meta = {
    description = cargo.package.description;
    mainProgram = "${branding.id}-theme";
    platforms = lib.platforms.linux;
  };
}
