# The installer: sudo strix-install on the ISO.
# lib.sh, i18n.sh, ui.sh, core.sh and frontend.sh only define functions, main.sh runs them.
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
  callPackage,
  systemd,
  util-linux,
  version,
  machineTemplate,
  machineLock ? null,
  # Colors of the default theme, from lib/themes.nix
  themeFile,
}:

let
  branding = import ../branding.nix;

  logo = callPackage ./logo.nix { };
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
    THEME_FILE = themeFile;
  };

  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./lib.sh
    ./i18n.sh
    ./ui.sh
    ./core.sh
    ./frontend.sh
    ./main.sh
  ];
}
