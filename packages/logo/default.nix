# The owl of the distro for every theme variant, as <theme>-<variant>.png: the owl and its
# double ring in the accent of the variant, the engraved lines in its terminal background, the
# eyes white. Beside it <theme>-<variant>-half.png and -closed.png, the frames of a blink.
# The theme engine draws it (render owl), rsvg-convert makes the PNGs.
# fastfetch shows the one of the session's theme (modules/apps/fastfetch.nix), the lock screen
# (shell/qml/Owl.qml) and the boot splash (packages/plymouth-theme) blink with them.
{ lib, runCommand, librsvg }:

{
  # The theme engine, the checked themes folder and its variants (lib/themes.nix)
  engine,
  themes,
  variants,
}:

let
  branding = import ../../branding.nix;
in
runCommand "${branding.id}-logos" { nativeBuildInputs = [ librsvg ]; } ''
  mkdir $out
  ${lib.concatMapStrings (v: ''
    for frame in "" -half -closed; do
      # An assignment fails the build if the engine fails
      svg=$(${lib.getExe engine} render owl$frame ${lib.escapeShellArg v.selection} --themes ${themes})
      rsvg-convert -w 512 -h 512 -o "$out/${v.theme}-${v.variant}$frame.png" <<<"$svg"
    done
  '') variants}
''
