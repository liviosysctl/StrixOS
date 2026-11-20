# The commands of everyday work on the distribution. `just` lists them.

# List the commands
default:
    @just --list

# Format everything: Nix, Rust, Lua, shell
fmt:
    nix fmt

# Every check CI runs on a push
check:
    nix flake check --print-build-logs

# Only how the code is kept: formatting, dead code, lints
lint:
    nix build --no-link --print-build-logs .#checks.x86_64-linux.format .#checks.x86_64-linux.lint

# Build the installer ISO
iso:
    nom build .#iso

# A test that boots virtual machines: theme, desktop, live, install
test name:
    nix build --print-build-logs .#tests.{{name}}

# Is the system the same as at another commit? For changes that only move code
same-system ref="main":
    #!/usr/bin/env bash
    set -euo pipefail
    before=$(tests/system-drv.sh {{ref}})
    after=$(tests/system-drv.sh)
    if [ "$before" = "$after" ]; then
      echo "The same system as {{ref}}."
    else
      echo "Not the same system as {{ref}}. What differs:"
      nix run nixpkgs#nix-diff -- "$before" "$after" | head -n 60
      exit 1
    fi

# What changed between two systems, package by package
diff old new:
    dix {{old}} {{new}}
