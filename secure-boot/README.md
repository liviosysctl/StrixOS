# Secure Boot

The installer ISO boots with Secure Boot on: shim, signed by Microsoft, starts
GRUB and the kernel when they are signed with the distribution's key. Its
certificate lives here as `<id>.crt`. The private key is the repository secret
`SECURE_BOOT_KEY` and nowhere else in the repository.

On a machine, the first start of the stick shows MokManager once: "Enroll key
from disk", the stick, `<id>.cer`, "Continue", "Yes", "Reboot". After that the
stick boots normally.

Installed machines sign their boot loader and kernels with a key of their own,
made at install time (`modules/secure-boot.nix`).

| What | Where |
|---|---|
| shim and MokManager | `packages/shim` (Debian's, signed by Microsoft and Debian) |
| GRUB with an SBAT section | `packages/grub-sb` |
| Signing the ISO | `packages/sign-iso`, run by CI after the build |
| Making the key, once | `nix run .#secure-boot-key -- FOLDER` |
| Installed machines | `modules/secure-boot.nix`, `packages/secure-boot` |
