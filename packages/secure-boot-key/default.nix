# Makes the distro's Secure Boot key, once:
#
#   nix run .#secure-boot-key -- ~/strix-secure-boot
#
# Run it in the repository. The private key stays in the given folder outside
# the repository, the certificate goes into secure-boot/<id>.crt. Every
# machine that enrolled the ISO's key trusts exactly this certificate, so a
# new key means enrolling again everywhere: the script refuses to replace one.
{ writeShellApplication, coreutils, openssl }:

let
  branding = import ../../branding.nix;
in
writeShellApplication {
  name = "secure-boot-key";
  runtimeInputs = [ coreutils openssl ];
  text = ''
    die() {
      printf 'secure-boot-key: %s\n' "$*" >&2
      exit 1
    }

    [ $# -eq 1 ] || die "usage: secure-boot-key FOLDER (outside the repository)"
    [ -f branding.nix ] && [ -d secure-boot ] || die "run this in the root of the repository"
    crt="secure-boot/${branding.id}.crt"
    [ ! -e "$crt" ] || die "$crt exists already. A new key means every machine has to enroll it again; delete the file first if that is really wanted."

    dir=$(realpath -m "$1")
    case $dir in
      "$(pwd)"*) die "the folder must be outside the repository, the key must never be committed" ;;
    esac
    install -d -m 0700 "$dir"
    [ ! -e "$dir/key.pem" ] || die "$dir/key.pem exists already"

    umask 077
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
      -subj "/CN=${branding.name} Secure Boot $(date +%Y)" \
      -addext "basicConstraints=critical,CA:FALSE" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" \
      -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
    umask 022
    install -m 0644 "$dir/cert.pem" "$crt"

    cat <<EOT
    Made the Secure Boot key of ${branding.name}.

      private key   $dir/key.pem   (keep a backup, never commit it)
      certificate   $crt

    Next:
      1. The key as the repository secret SECURE_BOOT_KEY, from this folder:
           gh secret set SECURE_BOOT_KEY < $dir/key.pem
         or on GitHub: Settings, Secrets and variables, Actions, paste the
         whole file including the BEGIN and END lines.
      2. Commit the certificate: git add $crt
    EOT
  '';
}
