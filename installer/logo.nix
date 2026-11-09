# The distro name in block letters, drawn once at build time
{ lib, runCommand, python3 }:

let
  branding = import ../branding.nix;
in
runCommand "${branding.id}-installer-logo" { } ''
  ${lib.getExe python3} ${./logo.py} ${lib.escapeShellArg branding.name} > $out
''
