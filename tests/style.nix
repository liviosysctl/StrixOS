# How the code is kept: formatted (treefmt.nix), without bindings nobody reads (deadnix) and
# without the patterns statix knows a shorter form for.
{
  self,
  pkgs,
  formatter,
}:

{
  format = formatter.check self;

  lint =
    pkgs.runCommand "check-lint"
      {
        nativeBuildInputs = [
          pkgs.deadnix
          pkgs.statix
        ];
      }
      ''
        cd ${self}
        deadnix --fail .
        statix check .
        touch $out
      '';
}
