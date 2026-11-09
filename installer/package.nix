# The installer. For now only a placeholder that proves it ends up in the ISO.
{ writeShellApplication, version }:

let
  branding = import ../branding.nix;
in
writeShellApplication {
  name = "${branding.id}-install";
  text = ''
    if [ "''${1:-}" = "--version" ]; then
      echo "${branding.name} ${version}"
      exit 0
    fi

    echo "${branding.name} ${version} installer"
    echo "Not ready yet: this placeholder only proves the installer is part of the ISO."
  '';
}
