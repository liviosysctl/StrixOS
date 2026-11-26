// The installer with the mock back end, for preview.sh: shows each page, saves it as a PNG in the
// folder Out.js names, then quits.
import QtQuick
import Strix
import "Out.js" as Out

Item {
    id: top
    width: 1040
    height: 700

    // (file name, setup in JS on the Installer `ui` and the back end `mock`)
    readonly property var shots: [
        ["0-language", "ui.page = 0"],
        ["0-language-de", "ui.pickLanguage('de_CH.UTF-8')"],
        ["1-network-offline", "ui.online = false; ui.networks = [ {ssid:'Fibernet',signal:82,secure:true}, {ssid:'Guest',signal:54,secure:false} ]; ui.page = 1"],
        ["2-timezone", "ui.online = true; ui.page = 2"],
        ["3-disk", "ui.page = 3; ui.diskIndex = 0"],
        ["3-disk-partition", "ui.spaceIndex = 3"],
        ["3-disk-free", "ui.diskIndex = 1; ui.spaceIndex = 1"],
        ["4-encryption", "ui.page = 4; ui.passphrase = 'correct horse'; ui.passphrase2 = 'correct'"],
        ["5-you", "ui.page = 5; ui.fullName = 'Livio Müller'; ui.password = 'secret'; ui.password2 = 'secret'"],
        ["6-summary-free", "ui.passphrase2 = 'correct horse'; ui.password = 'secret12'; ui.password2 = 'secret12'; ui.page = 6"],
        ["6-summary", "ui.diskIndex = 0; ui.spaceIndex = 3"],
        ["7-installing", "ui.erase = true; ui.install(); mock.event('step', {n: 6, total: 9}); for (let i = 0; i < 12; i++) mock.event('line', {text: 'copying path /nix/store/' + i + '-something'})"],
        ["8-done", "mock.event('done', {ok: true, error: '', mokCode: '4821', mokFromDisk: false})"],
        ["8-failed", "ui.page = 7; mock.event('done', {ok: false, error: 'nixos-install failed: no space left on device', mokCode: '', mokFromDisk: false}); ui.showLog = true"]
    ]
    property int shot: 0

    MockBackend { id: mock }
    Installer {
        id: ui
        anchors.fill: parent
        backend: mock
    }

    Timer {
        id: next
        interval: 700
        running: true
        onTriggered: {
            const script = top.shots[top.shot][1]
            new Function("ui", "mock", script)(ui, mock)
            settle.start()
        }
    }
    Timer {
        id: settle
        interval: 700
        onTriggered: {
            const name = top.shots[top.shot][0]
            ui.grabToImage(result => {
                result.saveToFile(Out.dir + "/" + name + ".png")
                console.info("ok  " + name)
                top.shot += 1
                if (top.shot < top.shots.length)
                    next.start()
                else
                    Qt.quit()
            })
        }
    }
}
