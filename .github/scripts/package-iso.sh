#!/usr/bin/env bash
# Prepares the release files of an ISO for the bootstick app:
#
#   package-iso.sh <tag> <iso> <outdir>
#
# Writes to <outdir>:
#   the ISO, or parts of it below 2 GiB (GitHub refuses larger release files)
#   SHA256SUMS      the whole ISO and every part, for sha256sum -c
#   manifest.json   what the bootstick app reads, see the plan (05-ci-releases)
#
# DISTRO_NAME is the display name for the manifest, SECURE_BOOT_SIGNED=true
# when the ISO was signed (then it boots with Secure Boot on). PART_BYTES and
# SPLIT_ABOVE only exist to test the splitting with a small file.
set -euo pipefail

tag=$1 iso=$(realpath "$2") out=$3
version=${tag#v}
name=$(basename "$iso")
size=$(stat -c %s "$iso")
part_bytes=${PART_BYTES:-$((1900 * 1024 * 1024))}
split_above=${SPLIT_ABOVE:-2000000000}
released=${RELEASED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

mkdir -p "$out"
cd "$out"
cp "$iso" "$name"
chmod u+w "$name"
iso_sha=$(sha256sum "$name" | cut -d ' ' -f 1)

parts='[]'
if [ "$size" -gt "$split_above" ]; then
  split --bytes="$part_bytes" --numeric-suffixes=0 --suffix-length=2 "$name" "$name.part"
  for part in "$name".part*; do
    parts=$(jq -c \
      --arg file "$part" \
      --argjson size "$(stat -c %s "$part")" \
      --arg sha256 "$(sha256sum "$part" | cut -d ' ' -f 1)" \
      '. + [{ file: $file, size: $size, sha256: $sha256 }]' <<<"$parts")
  done
fi

# The whole ISO is listed even when only its parts are uploaded: after joining
# the parts, sha256sum -c checks the result
{
  printf '%s  %s\n' "$iso_sha" "$name"
  jq -r '.[] | "\(.sha256)  \(.file)"' <<<"$parts"
} >SHA256SUMS

if [ "$parts" != '[]' ]; then
  rm "$name"
fi

jq -n \
  --arg name "${DISTRO_NAME:?}" \
  --arg version "$version" \
  --arg released "$released" \
  --arg file "$name" \
  --argjson size "$size" \
  --arg sha256 "$iso_sha" \
  --argjson parts "$parts" \
  --argjson signed "${SECURE_BOOT_SIGNED:-false}" \
  '{
    format: 1,
    name: $name,
    version: $version,
    released: $released,
    iso: { file: $file, size: $size, sha256: $sha256, parts: $parts },
    requirements: { uefi: true, secureBootOff: ($signed | not), ramGiB: 4, diskGiB: 32 }
  }' >manifest.json

ls -l
cat manifest.json
