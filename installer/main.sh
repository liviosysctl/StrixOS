usage() {
  cat <<EOF
Usage: ${DISTRO_ID}-install [options]

Without options, asks a few questions and installs ${DISTRO_NAME} on a disk.

  --core --answers FILE   Install from an answers file without asking.
                          The password must be in $password_file,
                          with encryption the passphrase in $luks_key_file.
  --hardware-nix FILE     Use this hardware.nix instead of detecting one (tests).
  --no-unmount            Leave /mnt mounted at the end (tests).
  --version               Print the version.
EOF
}

main() {
  local mode=frontend hardware_nix="" unmount=1
  answers_file=""

  while [ "$#" -gt 0 ]; do
    case $1 in
      --version)
        echo "${DISTRO_NAME} ${DISTRO_VERSION}"
        return 0
        ;;
      --core) mode=core ;;
      --answers)
        answers_file=${2:?--answers needs a file}
        shift
        ;;
      --hardware-nix)
        hardware_nix=${2:?--hardware-nix needs a file}
        shift
        ;;
      --no-unmount) unmount=0 ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        usage >&2
        return 64
        ;;
    esac
    shift
  done

  if [ "$mode" = core ]; then
    [ -n "$answers_file" ] || die "--core needs --answers FILE"
    install_from_answers "$hardware_nix" "$unmount"
  else
    answers_file="$work_dir/answers.json"
    run_frontend
  fi
}

main "$@"
