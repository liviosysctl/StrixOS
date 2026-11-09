# The installer: sudo strix-install on the ISO.
# lib.sh, core.sh and frontend.sh only define functions, main.sh runs them.
{
  lib,
  writeShellApplication,
  coreutils,
  curl,
  cryptsetup,
  disko,
  findutils,
  gawk,
  gnugrep,
  gum,
  jq,
  kbd,
  nix,
  nixos-install-tools,
  systemd,
  util-linux,
  version,
  machineTemplate,
  machineLock ? null,
}:

let
  branding = import ../branding.nix;
in
writeShellApplication {
  name = "${branding.id}-install";

  runtimeInputs = [
    coreutils
    curl
    cryptsetup
    disko
    findutils
    gawk
    gnugrep
    gum
    jq
    kbd
    nix
    nixos-install-tools
    systemd
    util-linux
  ];

  runtimeEnv = {
    DISTRO_ID = branding.id;
    DISTRO_NAME = branding.name;
    DISTRO_VERSION = version;
    STATE_VERSION = lib.trivial.release;
    TEMPLATE_DIR = machineTemplate;
    MACHINE_LOCK = if machineLock == null then "" else machineLock;
  };

  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./lib.sh
    ./core.sh
    ./frontend.sh
    ./main.sh
  ];
}
