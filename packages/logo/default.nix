# The owl of the distro for every theme variant, as <theme>-<variant>.png: the pen drawing of
# StrixUI, a horned owl standing a little sideways, its lines cream, its eyes in the accent of
# the variant and its pupils in the terminal background it is shown on.
# fastfetch shows the one of the session's theme (modules/fastfetch.nix).
{
  lib,
  runCommand,
  librsvg,
  jq,
}:

{
  # The theme engine, the checked themes folder and its variants (lib/themes.nix)
  engine,
  themes,
  variants,
  # StrixUI: the drawing, in the colours of Saturnus
  strixui,
}:

let
  branding = import ../../branding.nix;
  drawing = "${strixui}/design-system/assets/Logo/strix-owl.svg";
  # The two colours of the drawing that follow the theme
  accent = "#c8102e";
  ink = "#080707";
in
runCommand "${branding.id}-logos"
  {
    nativeBuildInputs = [
      librsvg
      jq
    ];
  }
  ''
    mkdir $out
    # A drawing without these colours would come out the same for every theme
    grep -q '${accent}' ${drawing} && grep -q '${ink}' ${drawing}
    ${lib.concatMapStrings (v: ''
      # An assignment fails the build if the engine fails
      tokens=$(${lib.getExe engine} render tokens ${lib.escapeShellArg v.selection} --themes ${themes})
      eyes=$(jq -er .colors.accent <<<"$tokens")
      pupils=$(jq -er .terminal.background <<<"$tokens")
      sed -e "s/${accent}/$eyes/g" -e "s/${ink}/$pupils/g" ${drawing} \
        | rsvg-convert -w 512 -h 512 -o $out/${v.theme}-${v.variant}.png
    '') variants}
  ''
