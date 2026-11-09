# Plymouth theme from theme data (colors) and the distro name.
{ lib, runCommand, python3, inter }:

{ theme }:

let
  branding = import ../../branding.nix;
  python = python3.withPackages (ps: [ ps.pillow ]);
  inherit (theme) colors;
in
runCommand "${branding.id}-plymouth-theme" { } ''
  ${lib.getExe python} ${./render.py} \
    $out/share/plymouth/themes/${branding.id} \
    ${lib.escapeShellArgs [ branding.id branding.name ]} \
    ${inter}/share/fonts/truetype/InterVariable.ttf \
    ${colors.background} ${colors.foreground} ${colors.accent} \
    ${./theme.script}
''
