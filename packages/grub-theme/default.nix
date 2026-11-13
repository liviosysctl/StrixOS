# A GRUB theme for one theme variant, in the look of StrixUI: the god's
# wallpaper darkened towards the left, the wordmark in fraktur with the motto,
# and a boot menu whose chosen row is raised and marked in the accent
# (render.py). GRUB draws text from bitmap fonts (.pf2), made here from
# JetBrains Mono.
{
  lib,
  runCommand,
  python3,
  grub2_efi,
  jq,
  jetbrains-mono,
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
  python = python3.withPackages (ps: [
    ps.pillow
    ps.fonttools
    ps.brotli
  ]);
  mono = "${jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";
  fontName = "${branding.name} Mono";
in
runCommand name { nativeBuildInputs = [ jq ]; } ''
  ${lib.getExe engine} render tokens ${lib.escapeShellArg selection} --themes ${themes} > tokens.json

  # A theme from a theme repository brings its own wallpaper; the gods have theirs in StrixUI
  dir=$(jq -r .dir tokens.json)
  theme=$(jq -r .theme tokens.json)
  wallpaper=-
  if [ -f "$dir/wallpaper.jpg" ]; then
    wallpaper=$dir/wallpaper.jpg
  elif [ -f ${strixui}/src/wallpapers/$theme.jpg ]; then
    wallpaper=${strixui}/src/wallpapers/$theme.jpg
  fi

  # StrixUI ships web fonts; Pillow wants plain TrueType
  ${lib.getExe python} -c '
  import sys
  from fontTools.ttLib import TTFont
  for src, dst in zip(sys.argv[1::2], sys.argv[2::2]):
      f = TTFont(src); f.flavor = None; f.save(dst)
  ' ${strixui}/src/fonts/GrenzeGotisch-Variable.woff2 fraktur.ttf \
    ${strixui}/src/fonts/IMFellEnglish-Italic.woff2 italic.ttf

  ${lib.getExe python} ${./render.py} $out tokens.json "$wallpaper" \
    ${lib.escapeShellArgs [ branding.name branding.motto ]} \
    fraktur.ttf italic.ttf ${mono} ${lib.escapeShellArg "${fontName} Regular"}

  for size in 14 16; do
    ${grub2_efi}/bin/grub-mkfont --size $size --name ${lib.escapeShellArg fontName} \
      --output $out/mono-$size.pf2 ${mono} 2>/dev/null
  done
''
