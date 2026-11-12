# The design system for the desktop, from the flake input strixui: the QML
# module (import Strix, import Strix.Shell), the wallpapers of the eight gods,
# the tokens and the fonts. Only data, nothing is compiled.
#
#   share/<id>-ui/qml       the QML module, for QML_IMPORT_PATH
#   share/<id>-ui/assets    the wallpapers; Theme.qml finds them as ../../assets
#   share/fonts/truetype    Grenze Gotisch, IM Fell English, JetBrains Mono
{ lib, stdenvNoCC, woff2, src }:

let
  branding = import ../../branding.nix;
  ds = "${src}/design-system";
in
stdenvNoCC.mkDerivation {
  pname = "${branding.id}-ui";
  version = "0-unstable-${src.lastModifiedDate or "0"}";
  inherit src;

  nativeBuildInputs = [ woff2 ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    share=$out/share/${branding.id}-ui
    mkdir -p $share $out/share/fonts/truetype $out/share/licenses/${branding.id}-ui
    cp -r ${ds}/qml ${ds}/assets ${ds}/themes ${ds}/tokens.json ${ds}/tokens.css ${ds}/README.md $share/

    # The design system ships WOFF2 for the web; fontconfig gets TrueType
    for font in ${ds}/fonts/*.woff2; do
      cp "$font" .
      woff2_decompress "$(basename "$font")"
    done
    install -m 0644 ./*.ttf $out/share/fonts/truetype/
    install -m 0644 ${ds}/fonts/LICENSE-* $out/share/licenses/${branding.id}-ui/
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    for file in qml/Strix/qmldir qml/Strix/Theme.qml qml/Strix/Shell/qmldir assets/Wallpapers/saturnus.jpg; do
      test -s $out/share/${branding.id}-ui/$file || { echo "missing: $file"; exit 1; }
    done
    test "$(ls $out/share/fonts/truetype/*.ttf | wc -l)" -ge 5
  '';

  meta = {
    description = "The design system of ${branding.name}: QML module, wallpapers and fonts";
    homepage = "https://github.com/liviosysctl/StrixUI";
    license = with lib.licenses; [ ofl ];
    platforms = lib.platforms.linux;
  };
}
