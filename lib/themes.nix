# Themes at build time: the theme engine, the checked themes folder, every
# variant and what is built from them (Plymouth themes, installer colors).
# Used by modules/theme.nix and by the flake (installer, checks).
{
  pkgs,
  # The folder with the themes of the distribution, one folder per theme
  # (design-system/themes of StrixUI)
  builtin,
  # More theme folders, by id, next to the built-in ones
  extraThemes ? { },
  # The theme a new installation starts with, <theme> or <theme>:<variant>
  default ? import ../themes/default.nix,
}:

let
  inherit (pkgs) lib;
  branding = import ../branding.nix;

  engine = pkgs.callPackage ../packages/theme-engine { };
  exe = lib.getExe engine;

  # Every folder in the built-in folder is a theme, the folder name is its id
  builtinThemes = lib.mapAttrs (themeId: _: "${builtin}/${themeId}") (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir builtin)
  );
  taken = builtins.attrNames (builtins.intersectAttrs builtinThemes extraThemes);
  sources =
    if taken == [ ] then
      builtinThemes // extraThemes
    else
      throw "extra themes may not use the id of a built-in theme: ${lib.concatStringsSep ", " taken}";

  # Read while evaluating, for the names of themes and variants only.
  # The engine checks everything else while building `dir`.
  data = lib.mapAttrs (_: path: lib.importTOML (path + "/theme.toml")) sources;

  # "<theme>" or "<theme>:<variant>" with the default variant filled in.
  # Returns { error = null; theme; variant; } or { error = "..."; }.
  resolve =
    text:
    let
      parts = lib.splitString ":" text;
      theme = builtins.head parts;
      known = lib.concatStringsSep ", " (builtins.attrNames data);
    in
    if builtins.length parts > 2 || theme == "" then
      { error = "\"${text}\" is not a theme, write it as <theme> or <theme>:<variant>"; }
    else if !(data ? ${theme}) then
      { error = "there is no theme \"${theme}\" (known: ${known})"; }
    else
      let
        variant = if builtins.length parts == 2 then builtins.elemAt parts 1 else data.${theme}.default-variant;
        variants = lib.concatStringsSep ", " (builtins.attrNames data.${theme}.variants);
      in
      if !(data.${theme}.variants ? ${variant}) then
        { error = "the theme \"${theme}\" has no variant \"${variant}\" (it has: ${variants})"; }
      else
        {
          error = null;
          inherit theme variant;
        };

  # The engine names Plymouth themes the same way, from PLYMOUTH_PREFIX
  plymouthPrefix = "${branding.id}-";
  plymouthName = theme: variant: "${plymouthPrefix}${theme}-${variant}";

  # The themes folder the system uses. Building it fails on any problem in
  # any theme, or if the default does not exist.
  dir = pkgs.runCommand "${branding.id}-themes" { } ''
    mkdir $out
    ${lib.concatStrings (
      lib.mapAttrsToList (themeId: path: ''
        cp -r ${path} $out/${themeId}
        chmod -R u+w $out/${themeId}
      '') sources
    )}
    ${exe} check $out --default ${lib.escapeShellArg default}
  '';

  variants = lib.concatLists (
    lib.mapAttrsToList (
      theme: themeData:
      map (variant: {
        inherit theme variant;
        selection = "${theme}:${variant}";
        plymouth = plymouthName theme variant;
      }) (builtins.attrNames themeData.variants)
    ) data
  );

  # One Plymouth theme per variant, so the splash can follow the theme
  plymouthThemes = map (
    v:
    pkgs.callPackage ../packages/plymouth-theme { } {
      name = v.plymouth;
      inherit (v) selection;
      inherit engine;
      themes = dir;
    }
  ) variants;

  # Colors for the console installer on the ISO, from the default theme
  installer = pkgs.runCommand "${branding.id}-installer-theme" { } ''
    ${exe} render installer ${lib.escapeShellArg default} --themes ${dir} > $out
  '';
in
{
  inherit
    engine
    builtinThemes
    dir
    data
    resolve
    default
    variants
    plymouthPrefix
    plymouthName
    plymouthThemes
    installer
    ;
}
