// A back end for the preview (preview.sh): canned answers, no computer touched.
import QtQuick

QtObject {
    id: root
    property bool online: true
    signal event(string name, var data)
    signal failed(string method, string message)

    function part(name, start, end, fsType, label, blocked) {
        return { kind: "partition", path: "/dev/" + name, start: start, end: end, bytes: (end - start + 1) * 512,
                 fsType: fsType, label: label, blocked: blocked }
    }

    function call(method, params, done) {
        const answers = {
            facts: { name: "Strix", id: "strix", version: "0.5.0", ramGib: 16, minRamGib: 4, minFreeGib: 48,
                     uefi: true, secureBoot: true, laptop: true,
                     disks: [ { path: "/dev/nvme0n1", stablePath: "/dev/disk/by-id/nvme-Samsung_990", bytes: 512110190592, model: "Samsung SSD 990 PRO", transport: "nvme",
                                // Windows 11 after C: was shrunk and D: made in the space
                                spaces: [ part("nvme0n1p1", 2048, 206847, "vfat", "", "esp"),
                                          part("nvme0n1p2", 206848, 239615, "", "", "msr"),
                                          part("nvme0n1p3", 239616, 498313215, "BitLocker", "", "bitlocker"),
                                          part("nvme0n1p5", 498313216, 998221823, "ntfs", "Daten", ""),
                                          part("nvme0n1p4", 998221824, 1000214527, "ntfs", "WinRE", "recovery") ],
                                bitlocker: true },
                              { path: "/dev/sda", stablePath: "/dev/disk/by-id/ata-WDC", bytes: 1000204886016, model: "WDC WD10EZEX", transport: "sata",
                                spaces: [ part("sda1", 2048, 838862847, "ext4", "Backup", ""),
                                          { kind: "free", path: "", start: 838862848, end: 1953523711, bytes: 570706362368, fsType: "", label: "", blocked: "" } ],
                                bitlocker: false } ] },
            timezones: ["Europe/Amsterdam", "Europe/Berlin", "Europe/London", "Europe/Paris", "Europe/Rome", "Europe/Vienna", "Europe/Zurich", "America/New_York", "Asia/Tokyo"],
            network: { online: root.online },
            "wifi.list": [ { ssid: "Fibernet", active: false, signal: 82, secure: true }, { ssid: "Guest", active: false, signal: 54, secure: false } ],
            state: { phase: "setup" },
            install: { started: true }
        }
        if (done) done(answers[method] !== undefined ? answers[method] : {})
    }
}
