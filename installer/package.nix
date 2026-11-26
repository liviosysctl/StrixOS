# The installer, installed as <id>-install: the core that installs from an answers file and the
# back end of the graphical installer (installer/gui). The crate has a neutral name; only the
# installed program carries the distro's. The unit tests run while building.
{
  lib,
  rustPlatform,
  makeWrapper,
  coreutils,
  cryptsetup,
  curl,
  disko,
  gptfdisk,
  networkmanager,
  nix,
  nixos-install-tools,
  ntfs3g,
  systemd,
  util-linux,
  version,
  machineTemplate,
  machineLock ? null,
}:

let
  branding = import ../branding.nix;
  cargo = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage {
  pname = "${branding.id}-install";
  inherit version;

  # The tests read the machine.nix template, so the source starts at the repo root
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ../templates/machine/machine.nix
    ];
  };
  buildAndTestSubdir = "installer";
  cargoRoot = "installer";
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mv $out/bin/installer $out/bin/${branding.id}-install
    wrapProgram $out/bin/${branding.id}-install \
      --set DISTRO_ID ${branding.id} \
      --set DISTRO_NAME ${lib.escapeShellArg branding.name} \
      --set DISTRO_VERSION ${version} \
      --set STATE_VERSION ${lib.trivial.release} \
      --set TEMPLATE_DIR ${machineTemplate} \
      --set MACHINE_LOCK ${if machineLock == null then "''" else machineLock} \
      --set-default NMCLI ${networkmanager}/bin/nmcli \
      --set-default INSTALL_COMMAND $out/bin/${branding.id}-install \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          cryptsetup
          curl
          disko
          # sgdisk: the two partitions next to Windows
          gptfdisk
          nix
          nixos-install-tools
          # ntfsls: which NTFS partition holds Windows, read without mounting it
          ntfs3g
          systemd
          util-linux
        ]
      }
  '';

  meta = {
    description = cargo.package.description;
    mainProgram = "${branding.id}-install";
    platforms = lib.platforms.linux;
  };
}
