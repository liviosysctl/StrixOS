#!/usr/bin/env bash
# Signs the boot files of installed machines with the distro key, as detached
# signatures (secure-boot/README.md):
#
#   sign-boot-files.sh
#
# Builds .#boot-files (GRUB and the kernel of the reference system), adds a
# secure-boot/signatures/<sha256>.p7 for every file that has none and removes
# the ones nothing lists any more. KEY_PEM is the private key from the secret
# SECURE_BOOT_KEY, the certificate is secure-boot/<id>.crt.
#
# Writes to $GITHUB_OUTPUT: changed (true when signatures were added or
# removed, the caller commits them) and complete (false when a file has no
# signature and there is no key to make one).
set -euo pipefail

id=$(nix eval --raw --file branding.nix id)
cert="secure-boot/$id.crt"
dir=secure-boot/signatures
output=${GITHUB_OUTPUT:-/dev/stdout}

files=$(nix build --no-link --print-out-paths -L .#boot-files)
sbsign="$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#sbsigntool)/bin/sbsign"

key=""
if [ -n "${KEY_PEM:-}" ]; then
  key=$(mktemp)
  trap 'rm -f "$key"' EXIT
  chmod 600 "$key"
  printf '%s\n' "$KEY_PEM" >"$key"
fi

changed=false complete=true
wanted=()
for file in "$files"/*; do
  sha=$(sha256sum <"$file" | cut -d ' ' -f 1)
  wanted+=("$sha.p7")
  [ -e "$dir/$sha.p7" ] && continue
  if [ -z "$key" ]; then
    echo "::error::$(basename "$file") ($sha) has no signature and there is no secret SECURE_BOOT_KEY to make one." >&2
    complete=false
    continue
  fi
  "$sbsign" --key "$key" --cert "$cert" --detached --output "$dir/$sha.p7" "$file" >/dev/null
  echo "Signed $(basename "$file"): $sha.p7"
  changed=true
done

for sig in "$dir"/*.p7; do
  [ -e "$sig" ] || continue
  name=$(basename "$sig")
  if [[ ! " ${wanted[*]} " =~ \ $name\  ]]; then
    rm -f "$sig"
    echo "Removed $name, no boot file has it any more"
    changed=true
  fi
done

printf 'changed=%s\ncomplete=%s\n' "$changed" "$complete" >>"$output"
