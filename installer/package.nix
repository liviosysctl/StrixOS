# The installer: sudo strix-install on the ISO.
# lib.sh, ui.sh, core.sh and frontend.sh only define functions, main.sh runs them.
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
  gnused,
  gum,
  jq,
  kbd,
  nix,
  ncurses,
  nixos-install-tools,
  python3,
  runCommand,
  systemd,
  util-linux,
  version,
  machineTemplate,
  machineLock ? null,
}:

let
  branding = import ../branding.nix;

  # The distro name in block letters, drawn once at build time
  logo = runCommand "${branding.id}-installer-logo" { } ''
    ${lib.getExe python3} ${./logo.py} ${lib.escapeShellArg branding.name} > $out
  '';
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
    gnused
    gum
    jq
    kbd
    ncurses
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
    LOGO_FILE = logo;
    MACHINE_LOCK = if machineLock == null then "" else machineLock;
  };

  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./lib.sh
    ./ui.sh
    ./core.sh
    ./frontend.sh
    ./main.sh
  ];
}
