# A GRUB theme for one theme variant, in the look of StrixUI: the god's
# wallpaper darkened towards the left, the wordmark in the serif italic with the motto,
# and a boot menu whose chosen row is raised and marked in the accent. The
# theme engine writes the pieces (draw grub), rsvg-convert draws the picture
# with the fonts of StrixUI. GRUB draws text from bitmap fonts (.pf2), made
# here from IBM Plex Mono.
{
  lib,
  runCommand,
  grub2_efi,
  jq,
  librsvg,
  makeFontsConf,
  woff2,
}:

{
  # Name of the folder, e.g. strix-saturnus-dark
  name,
  # <theme>:<variant>
  selection,
  # The theme engine and the checked themes folder (lib/themes.nix)
  engine,
  themes,
  # StrixUI: fonts and the wallpapers of the eight gods
  strixui,
}:

let
  branding = import ../../branding.nix;
  mono = "${fonts}/IBMPlexMono-Regular.ttf";
  fontName = "${branding.name} Mono";

  # StrixUI ships web fonts; fontconfig gets them as TrueType
  fonts = runCommand "${branding.id}-grub-fonts" { nativeBuildInputs = [ woff2 ]; } ''
    mkdir $out
    for font in CormorantGaramond-Italic-Variable IBMPlexMono-Regular; do
      cp ${strixui}/src/fonts/$font.woff2 $out/
      woff2_decompress $out/$font.woff2
      rm $out/$font.woff2
    done
  '';
  fontsConf = makeFontsConf {
    fontDirectories = [ fonts ];
  };
in
runCommand name
  {
    nativeBuildInputs = [
      jq
      librsvg
    ];
    FONTCONFIG_FILE = fontsConf;
  }
  ''
    # A theme from a theme repository brings its own wallpaper; the gods have theirs in StrixUI
    tokens=$(${lib.getExe engine} render tokens ${lib.escapeShellArg selection} --themes ${themes})
    dir=$(jq -r .dir <<<"$tokens")
    theme=$(jq -r .theme <<<"$tokens")
    variant=$(jq -r .variant <<<"$tokens")
    wallpaper=()
    if [ -f "$dir/wallpaper.jpg" ]; then
      wallpaper=(--wallpaper "$dir/wallpaper.jpg")
    elif [ "$variant" = light ] && [ -f ${strixui}/src/wallpapers/$theme-light.jpg ]; then
      # The light variant of a god has its own plate
      wallpaper=(--wallpaper ${strixui}/src/wallpapers/$theme-light.jpg)
    elif [ -f ${strixui}/src/wallpapers/$theme.jpg ]; then
      wallpaper=(--wallpaper ${strixui}/src/wallpapers/$theme.jpg)
    fi

    ${lib.getExe engine} draw grub $out ${lib.escapeShellArg selection} --themes ${themes} \
      --name ${lib.escapeShellArg branding.name} --motto ${lib.escapeShellArg branding.motto} \
      --font-name ${lib.escapeShellArg "${fontName} Regular"} "''${wallpaper[@]}"
    # PNG, not JPEG: the GRUB of the ISO is built without the jpeg module
    (cd $out && rsvg-convert background.svg -o background.png)
    rm -f $out/background.svg $out/wallpaper.jpg

    for size in 14 16; do
      ${grub2_efi}/bin/grub-mkfont --size $size --name ${lib.escapeShellArg fontName} \
        --output $out/mono-$size.pf2 ${mono} 2>/dev/null
    done
  ''
