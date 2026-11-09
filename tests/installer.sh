# Unit tests for the installer functions. Run by checks.installer-functions
# in the Nix sandbox: no disks, no root, no network. Disk and system lookups
# are replaced by small stand-ins.
set -euo pipefail

export DISTRO_ID=strix DISTRO_NAME=Strix DISTRO_VERSION=0.0.0 STATE_VERSION=26.11
export TEMPLATE_DIR=$1 LOGO_FILE=$2 MACHINE_LOCK=""
installer=$3 glyphs=$4 console_font=$5

# shellcheck source=/dev/null
source "$installer/lib.sh"
# shellcheck source=/dev/null
source "$installer/i18n.sh"
# shellcheck source=/dev/null
source "$installer/ui.sh"
# shellcheck source=/dev/null
source "$installer/core.sh"
# shellcheck source=/dev/null
source "$installer/frontend.sh"

work=$(mktemp -d)
log_file=$work/install.log
: >"$log_file"

failed=0
check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failed=1
  fi
}

# Stand-ins for lookups that need a real system
getent() { [ "$2" = existing ]; }
valid_time_zone() { [ "$1" = Europe/Zurich ]; }

check "user name proposal" '[ "$(propose_user_name "Livio Müller")" = livio ]'
check "umlauts" '[ "$(propose_user_name "Jürg Meier")" = juerg ]'
check "name starting with a digit" '[ "$(propose_user_name "3D Max")" = user3d ]'
check "valid user name" 'valid_user_name livio'
check "user name with capitals" '! valid_user_name Root'
check "user name root" '! valid_user_name root'
check "user name equal to the distro" '! valid_user_name "$DISTRO_ID"'
check "user name that exists" '! valid_user_name existing'
check "valid host name" 'valid_host_name livio-laptop'
check "host name with _" '! valid_host_name livio_laptop'
check "host name ending in -" '! valid_host_name livio-'
check "full name with quotes" 'valid_full_name "Livio \"LD\" Müller"'
check "empty full name" '! valid_full_name ""'
check "full name with a newline" '! valid_full_name "$(printf "a\nb")"'
check "locale" 'valid_locale de_CH.UTF-8 && ! valid_locale xx_XX.UTF-8'
check "keyboard ch" '[ "$(keyboard_settings ch)" = "sg ch " ]'
check "keyboard ch-fr" '[ "$(keyboard_settings ch-fr)" = "fr_CH ch fr" ]'
check "unknown keyboard" '! keyboard_settings xx'
check "swap with hibernation" '[ "$(swap_size 16 true)" = 17G ]'
check "swap with little RAM" '[ "$(swap_size 4 false)" = 4G ]'
check "swap capped at 8G" '[ "$(swap_size 32 false)" = 8G ]'
check "hibernation fits 64/8" 'hibernation_fits 64 8'
check "hibernation does not fit 40/8" '! hibernation_fits 40 8'
check "escape quotes" '[ "$(nix_escape "a\"b")" = "a\\\"b" ]'
check "escape interpolation" '[ "$(nix_escape "x\${y}")" = "x\\\${y}" ]'
check "escape backslash" '[ "$(nix_escape "a\\b")" = "a\\\\b" ]'

# The disk list from a fake lsblk: sdb is the boot stick, sdc too small,
# zram and the CD are not disks to install on
lsblk() {
  cat <<'JSON'
{"blockdevices":[
 {"name":"sda","path":"/dev/sda","size":42949672960,"type":"disk","tran":"sata","model":"VMware Virtual S  ","ro":false},
 {"name":"sdb","path":"/dev/sdb","size":64424509440,"type":"disk","tran":"usb","model":"Stick","ro":false},
 {"name":"sdc","path":"/dev/sdc","size":21474836480,"type":"disk","tran":"sata","model":"Small","ro":false},
 {"name":"nvme0n1","path":"/dev/nvme0n1","size":1000204886016,"type":"disk","tran":"nvme","model":null,"ro":false},
 {"name":"sr0","path":"/dev/sr0","size":1610612736,"type":"rom","tran":"sata","model":"CD","ro":true},
 {"name":"zram0","path":"/dev/zram0","size":42949672960,"type":"disk","tran":null,"model":null,"ro":false}
]}
JSON
}
boot_disk() { echo sdb; }
disks=$(candidate_disks)
check "disk list: sda and nvme0n1 only" '[ "$(cut -f 1 <<<"$disks" | tr "\n" " ")" = "/dev/sda /dev/nvme0n1 " ]'
check "disk model trimmed" 'grep -qP "^/dev/sda\t42949672960\tVMware Virtual S\tsata$" <<<"$disks"'
check "disk without a model" 'grep -qP "^/dev/nvme0n1\t1000204886016\tDisk\tnvme$" <<<"$disks"'
unset -f lsblk boot_disk

# Reading the answers, including false values (the first VMware run failed
# here because jq -e treats false as an error)
answers_file=$work/answers.json
cat >"$answers_file" <<'JSON'
{
  "hostName": "strix-test",
  "timeZone": "Europe/Zurich",
  "locale": "de_CH.UTF-8",
  "keyboard": "ch",
  "user": { "name": "livio", "fullName": "Livio" },
  "disk": "/dev/null",
  "encrypt": false,
  "hibernation": false
}
JSON
# Reads the same fields as read_answers, but skips its checks of the disk and
# the time zone, which need a real system
read_answers_without_disk() {
  host_name=$(answer .hostName)
  encrypt=$(answer .encrypt)
  hibernation=$(answer .hibernation)
  full_name=$(answer .user.fullName)
}
# Outside of check: bash ignores set -e inside an if, and the original bug
# was exactly a silent exit through set -e
set +e
(
  set -e
  read_answers_without_disk
  [ "$encrypt" = false ] && [ "$hibernation" = false ]
)
read_status=$?
set -e
check "answers with false values" '[ "$read_status" -eq 0 ]'
check "answers with true values" 'jq ".encrypt = true" "$answers_file" >"$work/a2" && answers_file=$work/a2 && [ "$(answer .encrypt)" = true ]'
check "missing answer is an error" '! (answer .nothing >/dev/null 2>&1)'

# machine.nix with tricky free text and VMware detected
host_name=livio-laptop time_zone=Europe/Zurich locale=de_CH.UTF-8 keyboard=ch user_name=livio
full_name='Tom "TJ" & ${Jerry} @hostName@ \ end'
disk=/dev/disk/by-id/ata-disk encrypt=true swap=17G hibernation=true virtualization=vmware
out=$(render_machine_nix "$TEMPLATE_DIR/machine.nix")
check "no placeholders left" '! sed /description/d <<<"$out" | grep -qE "@[A-Za-z]+@"'
check "full name escaped" 'grep -qF "description = \"Tom \\\"TJ\\\" & \\\${Jerry} @hostName@ \\\\ end\";" <<<"$out"'
check "VMware guest tools" 'grep -q "virtualisation.vmware.guest.enable = true;" <<<"$out"'
check "keyboard filled in" 'grep -q "console.keyMap = \"sg\";" <<<"$out" && grep -q "layout = \"ch\";" <<<"$out"'
check "state version" 'grep -q "system.stateVersion = \"26.11\";" <<<"$out"'
virtualization=none
check "no VMware line on real hardware" '! grep -q vmware <<<"$(render_machine_nix "$TEMPLATE_DIR/machine.nix")"'

# Translations: every language has the same keys and the same number of %s
same_keys() {
  local lang=$1 key
  local -n table="tr_$lang"
  [ "${#table[@]}" -eq "${#tr_en[@]}" ] || return 1
  for key in "${!tr_en[@]}"; do
    [ -n "${table[$key]+set}" ] || return 1
    [ "$(grep -o "%s" <<<"${table[$key]}" | wc -l)" = "$(grep -o "%s" <<<"${tr_en[$key]}" | wc -l)" ] || return 1
  done
}
for lang in de fr it; do
  check "translation $lang complete" "same_keys $lang"
done

# Every key the installer asks for exists. Most appear as t KEY or tf KEY,
# the rest are listed in code (step hints, summary rows, step titles).
used_keys=$(
  {
    grep -ohE '\$\(tf? [a-z][a-z0-9_]*' "$installer"/*.sh | awk '{ print $2 }'
    grep -ohE 'summary_row l_[a-z]+' "$installer"/frontend.sh | awk '{ print $2 }'
    printf '%s\n' "${step_hints[@]}"
    for i in $(seq 1 "$total_steps"); do echo "st$i"; done
  } | sort -u
)
missing_keys=""
for key in $used_keys; do
  [ -n "${tr_en[$key]+set}" ] || missing_keys+=" $key"
done
check "every used text exists${missing_keys:+:$missing_keys}" '[ -z "$missing_keys" ]'

check "language from the locale" '[ "$(ui_lang_for_locale fr_CH.UTF-8)" = fr ] && [ "$(ui_lang_for_locale en_GB.UTF-8)" = en ]'
check "text in the chosen language" 'ui_lang=it; [ "$(t b_no)" = No ] && [ "$(t s_disk)" = Disco ]'
check "text with a value" 'ui_lang=de; [ "$(tf d_title Strix)" = "Strix ist installiert." ]'
ui_lang=en
check "padding counts characters" 'LC_ALL=C.UTF-8; [ "$(pad "Verschlüsselung" 16)" = "Verschlüsselung " ]'
check "console font has every character" 'python3 "$glyphs" "$console_font" "$installer"/*.sh'

# Every language on the first screen is supported and brings a keyboard
# the core knows
locales_ok() {
  local i
  for ((i = 0; i < ${#languages[@]}; i += 2)); do
    valid_locale "${languages[$i]}" || return 1
    keyboard_settings "$(default_keyboard "${languages[$i]}")" >/dev/null || return 1
  done
}
check "languages and their keyboards" 'locales_ok'
keyboards_ok() {
  local -a list
  local i
  mapfile -t list < <(keyboards)
  for ((i = 0; i < ${#list[@]}; i += 2)); do
    keyboard_settings "${list[$i]}" >/dev/null || return 1
  done
}
check "every keyboard on the screen is known" 'keyboards_ok'
check "label of a key" '[ "$(label_of fr_CH.UTF-8 "${languages[@]}")" = "Français (Suisse)" ]'

# The logo: only letter, shadow and empty pixels
check "logo characters" '! grep -q "[^#s.]" "$LOGO_FILE"'

exit "$failed"
