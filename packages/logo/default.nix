# The owl of the distro for every theme variant, as <theme>-<variant>.png: the owl and its
# double ring in the accent of the variant, the engraved lines in its terminal background, the
# eyes white. fastfetch shows the one of the session's theme (modules/fastfetch.nix).
{ lib, runCommand, python3, librsvg, jq }:

{
  # The theme engine, the checked themes folder and its variants (lib/themes.nix)
  engine,
  themes,
  variants,
}:

let
  branding = import ../../branding.nix;
in
runCommand "${branding.id}-logos" { nativeBuildInputs = [ python3 librsvg jq ]; } ''
  mkdir $out
  ${lib.concatMapStrings (v: ''
    # An assignment fails the build if the engine fails
    tokens=$(${lib.getExe engine} render tokens ${lib.escapeShellArg v.selection} --themes ${themes})
    accent=$(jq -er .colors.accent <<<"$tokens")
    background=$(jq -er .terminal.background <<<"$tokens")
    python3 ${./owl.py} "$accent" "$background" > owl.svg
    rsvg-convert -w 512 -h 512 owl.svg -o $out/${v.theme}-${v.variant}.png
  '') variants}
''
