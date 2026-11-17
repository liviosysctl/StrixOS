# A Plymouth theme for one theme variant: the owl, the distro name as
# wordmark, the colors from the theme engine. The engine writes the pieces
# (draw plymouth), rsvg-convert draws the wordmark in Inter ExtraBold.
{
  lib,
  runCommand,
  imagemagick,
  inter,
  librsvg,
  makeFontsConf,
}:

{
  # Name of the Plymouth theme, e.g. strix-chamber-dark
  name,
  # <theme>:<variant>
  selection,
  # The theme engine and the checked themes folder (lib/themes.nix)
  engine,
  themes,
  # The owl of the variant without its ending, <logos>/<theme>-<variant> (packages/logo)
  owl,
}:

let
  branding = import ../../branding.nix;
in
runCommand name
  {
    nativeBuildInputs = [
      imagemagick
      librsvg
    ];
    FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ inter ]; };
  }
  ''
    dir=$out/share/plymouth/themes/${name}
    ${lib.getExe engine} draw plymouth $dir ${lib.escapeShellArg selection} --themes ${themes} \
      --id ${name} --name ${lib.escapeShellArg branding.name} --script ${./theme.script}
    # Cut to the letters: the script scales the wordmark by its height
    rsvg-convert $dir/wordmark.svg | magick png:- -trim +repage PNG32:$dir/wordmark.png
    rm $dir/wordmark.svg
    for frame in "" -half -closed; do
      cp "${owl}$frame.png" "$dir/owl$frame.png"
    done
  ''
