#!/usr/bin/env bash
# Signs the ISO for Secure Boot in CI (packages/sign-iso, secure-boot/README.md):
#
#   sign-iso.sh <iso> <outdir>
#
# KEY_PEM is the private key from the secret SECURE_BOOT_KEY, the certificate
# is secure-boot/<id>.crt. Without either, the ISO stays unsigned: a warning,
# or an error when REQUIRE_SIGNATURE is true (a release).
#
# Writes to $GITHUB_OUTPUT: iso (the file to use from here on) and signed.
set -euo pipefail

iso=$1 out=$2
id=$(nix eval --raw --file branding.nix id)
cert="secure-boot/$id.crt"
output=${GITHUB_OUTPUT:-/dev/stdout}

if [ -z "${KEY_PEM:-}" ] || [ ! -f "$cert" ]; then
  message="No secret SECURE_BOOT_KEY or no $cert: the ISO is not signed and only boots with Secure Boot off."
  if [ "${REQUIRE_SIGNATURE:-false}" = true ]; then
    echo "::error::$message" >&2
    exit 1
  fi
  echo "::warning::$message"
  printf 'iso=%s\nsigned=false\n' "$iso" >>"$output"
  exit 0
fi

key=$(mktemp)
trap 'rm -f "$key"' EXIT
chmod 600 "$key"
printf '%s\n' "$KEY_PEM" >"$key"

mkdir -p "$out"
signed="$out/$(basename "$iso")"
SECURE_BOOT_KEY=$key SECURE_BOOT_CERT=$cert nix run .#sign-iso -- "$iso" "$signed"
printf 'iso=%s\nsigned=true\n' "$signed" >>"$output"
