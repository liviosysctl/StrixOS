# One formatter for the whole repository: `nix fmt` rewrites, the check `format` (CI) refuses what
# is not formatted. Nix by nixfmt, Rust by rustfmt, Lua by StyLua, shell by shfmt.
{ pkgs, ... }:

{
  runtimeInputs = [
    pkgs.nixfmt
    pkgs.rustfmt
    pkgs.stylua
    pkgs.shfmt
  ];

  settings = {
    tree-root-file = "flake.nix";
    # QML, TOML, Markdown and the rest have no formatter here
    on-unmatched = "debug";

    formatter = {
      nix = {
        command = "nixfmt";
        includes = [ "*.nix" ];
        # Templates hold @placeholders@ until the installer fills them: not Nix yet
        excludes = [
          "templates/machine/*"
          "tests/fixtures/machine.nix"
        ];
      };
      rust = {
        command = "rustfmt";
        options = [
          "--edition"
          "2024"
        ];
        includes = [ "*.rs" ];
      };
      lua = {
        command = "stylua";
        includes = [ "*.lua" ];
        # The files of Neovim hold @placeholders@ until the build fills them: not Lua yet
        excludes = [ "shell/nvim/*" ];
      };
      shell = {
        command = "shfmt";
        options = [
          "--write"
          "--indent"
          "2"
          "--case-indent"
          "--binary-next-line"
          "--language-dialect"
          "bash"
        ];
        includes = [ "*.sh" ];
      };
    };
  };
}
