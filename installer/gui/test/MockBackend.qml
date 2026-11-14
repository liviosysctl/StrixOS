// A back end for the preview (preview.py): canned answers, no computer touched.
import QtQuick

QtObject {
    id: root
    property bool online: true
    signal event(string name, var data)
    signal failed(string method, string message)

    function call(method, params, done) {
        const answers = {
            facts: { name: "Strix", id: "strix", version: "0.5.0", ramGib: 16, minRamGib: 4, minFreeGib: 48,
                     uefi: true, secureBoot: true, laptop: true,
                     disks: [ { path: "/dev/nvme0n1", stablePath: "/dev/disk/by-id/nvme-Samsung_990", bytes: 512110190592, model: "Samsung SSD 990 PRO", transport: "nvme" },
                              { path: "/dev/sda", stablePath: "/dev/disk/by-id/ata-WDC", bytes: 1000204886016, model: "WDC WD10EZEX", transport: "sata" } ] },
            timezones: ["Europe/Amsterdam", "Europe/Berlin", "Europe/London", "Europe/Paris", "Europe/Rome", "Europe/Vienna", "Europe/Zurich", "America/New_York", "Asia/Tokyo"],
            network: { online: root.online },
            "wifi.list": [ { ssid: "Fibernet", active: false, signal: 82, secure: true }, { ssid: "Guest", active: false, signal: 54, secure: false } ],
            state: { phase: "setup" },
            install: { started: true }
        }
        if (done) done(answers[method] !== undefined ? answers[method] : {})
    }
}
