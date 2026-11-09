# Shared helpers for the installer: logging, validation, escaping, disks.
# DISTRO_ID, DISTRO_NAME, DISTRO_VERSION, STATE_VERSION, TEMPLATE_DIR and
# MACHINE_LOCK come from runtimeEnv in package.nix.

# Bash 5.2 treats & in ${var//pattern/replacement} as the match. A full name
# like "Tom & Jerry" must stay as typed.
shopt -u patsub_replacement 2>/dev/null || true

work_dir="/run/${DISTRO_ID}-install"
log_file="/tmp/${DISTRO_ID}-install.log"
password_file="$work_dir/user.pass"
# Must match passwordFile in modules/storage/btrfs.nix
luks_key_file="/tmp/${DISTRO_ID}-luks.key"
# Must match the LUKS name in modules/storage/btrfs.nix
luks_name="cryptsystem"

min_ram_kib=$((4 * 1024 * 1024))
min_disk_bytes=$((32 * 1024 * 1024 * 1024))
# Space left for the system and /home after the swap file, in GiB
min_free_gib=48

log() {
  printf '%s\n' "$*" | tee -a "$log_file" >&2
}

die() {
  printf 'Error: %s\n' "$*" | tee -a "$log_file" >&2
  exit 1
}

# Runs a command, shows its output and keeps it in the log
run() {
  "$@" 2>&1 | tee -a "$log_file"
}

# Escapes free text for a string in a Nix file
nix_escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//\$\{/\\\$\{}
  printf '%s' "$text"
}

valid_user_name() {
  local name=$1
  [[ $name =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  case $name in
    root | nixos | nobody | "$DISTRO_ID") return 1 ;;
  esac
  ! getent passwd "$name" >/dev/null
}

valid_host_name() {
  [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

valid_full_name() {
  local name=$1
  [ -n "$name" ] && [ "${#name}" -le 64 ] && [[ $name != *$'\n'* ]]
}

valid_time_zone() {
  [[ $1 =~ ^[A-Za-z0-9_+/-]+$ ]] && [ -e "/etc/zoneinfo/$1" ]
}

valid_locale() {
  case $1 in
    de_CH.UTF-8 | fr_CH.UTF-8 | it_CH.UTF-8 | de_DE.UTF-8 | en_US.UTF-8 | en_GB.UTF-8) return 0 ;;
  esac
  return 1
}

# Keyboard code -> "consoleKeyMap xkbLayout xkbVariant" (variant may be empty)
keyboard_settings() {
  case $1 in
    ch) echo "sg ch " ;;
    ch-fr) echo "fr_CH ch fr" ;;
    de) echo "de de " ;;
    fr) echo "fr fr " ;;
    us) echo "us us " ;;
    *) return 1 ;;
  esac
}

# Turns "Livio Müller" into "livio"
propose_user_name() {
  local first=${1%% *}
  first=${first,,}
  first=${first//ä/ae}
  first=${first//ö/oe}
  first=${first//ü/ue}
  first=${first//é/e}
  first=${first//è/e}
  first=${first//à/a}
  first=${first//[^a-z0-9]/}
  [[ $first =~ ^[a-z_] ]] || first="user$first"
  printf '%s' "${first:0:32}"
}

ram_kib() {
  awk '/^MemTotal:/ { print $2 }' /proc/meminfo
}

disk_bytes() {
  lsblk --bytes --nodeps --noheadings --output SIZE "$1"
}

# The disk the live system was started from, so it is never offered
boot_disk() {
  local source parent
  source=$(findmnt --noheadings --output SOURCE /iso 2>/dev/null || true)
  [ -n "$source" ] || return 0
  parent=$(lsblk --noheadings --output PKNAME "$source" 2>/dev/null | head -n 1 || true)
  if [ -n "$parent" ]; then
    printf '%s\n' "$parent"
  else
    basename "$source"
  fi
}

# Disks that can be installed on, one per line: path, size in bytes, model, transport
candidate_disks() {
  local boot
  boot=$(boot_disk)
  lsblk --json --bytes --nodeps --output NAME,PATH,SIZE,TYPE,TRAN,MODEL,RO |
    jq -r --arg boot "$boot" --argjson min "$min_disk_bytes" '
      .blockdevices[]
      | select(.type == "disk")
      | select(.ro | not)
      | select(.name != $boot)
      | select(.name | startswith("zram") | not)
      | select(.size >= $min)
      | [.path, (.size | tostring), ((.model // "Disk") | gsub("\\s+$"; "")), (.tran // "")]
      | @tsv'
}

# A path for the disk that does not change between boots, if one exists.
# disko only uses it while formatting; the installed system mounts by
# partition label, so the plain path is a safe fallback.
stable_disk_path() {
  local device=$1 link name rank best="" best_rank=99
  for link in /dev/disk/by-id/*; do
    [ -e "$link" ] || continue
    name=${link##*/}
    [[ $name == *-part* ]] && continue
    [ "$(readlink -f "$link")" = "$device" ] || continue
    case $name in
      nvme-eui.*) rank=6 ;;
      nvme-*) rank=1 ;;
      ata-*) rank=2 ;;
      scsi-*) rank=3 ;;
      usb-*) rank=4 ;;
      wwn-*) rank=5 ;;
      *) rank=7 ;;
    esac
    if [ "$rank" -lt "$best_rank" ]; then
      best=$link
      best_rank=$rank
    fi
  done
  printf '%s\n' "${best:-$device}"
}

# Whether hibernation fits: swap as large as the RAM plus 1 GiB, and enough
# space left for the system
hibernation_fits() {
  local disk_gib=$1 ram_gib=$2
  [ $((disk_gib - ram_gib - 1)) -ge "$min_free_gib" ]
}

# Swap size for the answers, e.g. "17G"
swap_size() {
  local ram_gib=$1 hibernation=$2
  if [ "$hibernation" = true ]; then
    echo "$((ram_gib + 1))G"
  elif [ "$ram_gib" -lt 8 ]; then
    echo "${ram_gib}G"
  else
    echo "8G"
  fi
}

ram_gib() {
  local kib
  kib=$(ram_kib)
  echo $(((kib + 1048575) / 1048576))
}

is_laptop() {
  grep -qs Battery /sys/class/power_supply/*/type
}

check_root() {
  [ "$(id -u)" -eq 0 ] || die "Run the installer with sudo: sudo ${DISTRO_ID}-install"
}

check_uefi() {
  [ -d /sys/firmware/efi/efivars ] ||
    die "${DISTRO_NAME} needs UEFI. Switch the firmware from Legacy/CSM to UEFI. In VMware: VM Settings, Options, Advanced, Firmware type UEFI."
}

check_ram() {
  [ "$(ram_kib)" -ge "$min_ram_kib" ] ||
    die "${DISTRO_NAME} needs at least 4 GiB of RAM to install."
}

network_ok() {
  curl --silent --head --fail --max-time 5 https://cache.nixos.org/nix-cache-info >/dev/null
}
