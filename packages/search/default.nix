# The search service, installed as <id>-search (e.g. strix-search), with the system menu and the
# command files of shell/ next to it. The crate has a neutral name; only the installed program
# carries the distro's. The unit tests (golden queries, the 5 ms budget) run while building.
{ lib, rustPlatform, makeWrapper }:

let
  branding = import ../../branding.nix;
  cargo = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage {
  pname = "${branding.id}-search";
  inherit (cargo.package) version;

  # The tests read shell/menu.toml and shell/commands, so the source is the repository root
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./fixtures
      ../../shell
    ];
  };
  buildAndTestSubdir = "packages/search";
  cargoRoot = "packages/search";
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mkdir -p $out/share/${branding.id}-search
    cp -r ${../../shell}/menu.toml ${../../shell}/settings.toml ${../../shell}/commands $out/share/${branding.id}-search/
    mv $out/bin/search $out/bin/.${branding.id}-search
    makeWrapper $out/bin/.${branding.id}-search $out/bin/${branding.id}-search \
      --set-default SEARCH_ID ${branding.id} \
      --set-default MENU_FILE $out/share/${branding.id}-search/menu.toml \
      --set-default SETTINGS_FILE $out/share/${branding.id}-search/settings.toml \
      --set-default COMMANDS_DIR $out/share/${branding.id}-search/commands
  '';

  meta = {
    description = cargo.package.description;
    mainProgram = "${branding.id}-search";
    platforms = lib.platforms.linux;
  };
}
