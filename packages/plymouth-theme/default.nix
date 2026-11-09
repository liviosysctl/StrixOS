# A Plymouth theme for one theme variant: the distro name as wordmark, the
# colors from the theme engine.
{ lib, runCommand, python3, inter }:

{
  # Name of the Plymouth theme, e.g. strix-chamber-dark
  name,
  # <theme>:<variant>
  selection,
  # The theme engine and the checked themes folder (lib/themes.nix)
  engine,
  themes,
}:

let
  branding = import ../../branding.nix;
  python = python3.withPackages (ps: [ ps.pillow ]);
in
runCommand name { } ''
  # Background, text and accent as rrggbb. An assignment fails the build if the engine fails.
  colors=$(${lib.getExe engine} render plymouth ${lib.escapeShellArg selection} --themes ${themes})
  read -r background foreground accent <<<"$colors"
  ${lib.getExe python} ${./render.py} \
    $out/share/plymouth/themes/${name} \
    ${lib.escapeShellArgs [ name branding.name ]} \
    ${inter}/share/fonts/truetype/InterVariable.ttf \
    "$background" "$foreground" "$accent" \
    ${./theme.script}
''
