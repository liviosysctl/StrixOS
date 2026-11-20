#!/usr/bin/env bash
# The derivation of the reference machine's system at a commit, without its copy of the source
# tree, which changes with every commit. Two commits with the same line build the same system:
#   tests/system-drv.sh            the working tree
#   tests/system-drv.sh main       a branch, a tag or a commit
# After moving code around, the line must not change (just same-system main).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
ref=${1:-}
flake="git+file://$PWD"
[ -z "$ref" ] || flake="$flake?rev=$(git rev-parse "$ref")"

id=$(nix eval --raw --file branding.nix id)
nix eval --raw "$flake#nixosConfigurations.$id-reference" --apply '
  system:
  (system.extendModules {
    modules = [ ({ lib, ... }: { system.extraDependencies = lib.mkForce [ ]; }) ];
  }).config.system.build.toplevel.drvPath'
echo
