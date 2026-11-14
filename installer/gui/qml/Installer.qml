// The graphical installer: the window's content, a wizard in the manner of Fedora's installer.
// Steps on the left, one question per page on the right, Back and Next below. It only asks; the
// back end (backend.py, through `backend`) knows the computer and installs.
//
// Plain QtQuick and the Strix module, so a test can load it without Quickshell (test/preview.py).
// Texts.js comes from the build (installer/gui/default.nix) or the test.
//   backend.call(method, params, done)   and the signal backend.event(name, data)
import QtQuick
import Strix
// Every text of the installer in every language, written when the package is built
// (`<id>-install --texts`), so the window has its words before the back end answers
import "Texts.js" as Texts

Item {
    id: root

    /// The line to the back end: call(method, params, done) and signal event(name, data).
    property var backend
    /// Fired when the keyboard changes, so the session types with it at once.
    signal keyboardChosen(string layout, string variant)
    /// The window should close (it only hides; the installation goes on).
    signal closeRequested()

    implicitWidth: 1040
    implicitHeight: 700

    // ---------------------------------------------------------------- texts

    property var texts: Texts.all
    property string lang: "en"
    function t(key) {
        const own = texts[lang] || {}
        const en = texts.en || {}
        return own[key] !== undefined ? own[key] : (en[key] !== undefined ? en[key] : "")
    }
    /// t with %s filled in, and %% as in printf
    function tf(key, value) { return t(key).replace("%s", value).replace("%%", "%") }

    // ---------------------------------------------------------------- the computer

    property var facts: ({ name: "Strix", id: "strix", version: "", ramGib: 0, minFreeGib: 48, secureBoot: false, laptop: false, disks: [] })
    property bool online: false
    property var zones: []
    property var networks: []
    property bool scanning: false

    // ---------------------------------------------------------------- the answers

    readonly property var languages: [
        ["en_US.UTF-8", "English (US)"], ["en_GB.UTF-8", "English (UK)"],
        ["de_CH.UTF-8", "Deutsch (Schweiz)"], ["de_DE.UTF-8", "Deutsch (Deutschland)"],
        ["fr_CH.UTF-8", "Français (Suisse)"], ["it_CH.UTF-8", "Italiano (Svizzera)"]
    ]
    // code, text key, xkb layout, xkb variant (lib.sh keyboard_settings)
    readonly property var keyboards: [
        ["ch", "kb_ch", "ch", ""], ["ch-fr", "kb_ch_fr", "ch", "fr"], ["de", "kb_de", "de", ""],
        ["fr", "kb_fr", "fr", ""], ["it", "kb_it", "it", ""], ["gb", "kb_gb", "gb", ""], ["us", "kb_us", "us", ""]
    ]

    property string locale: "en_US.UTF-8"
    // The live session starts with the Swiss German layout, like the console
    property string keyboard: "ch"
    property string timeZone: "Europe/Zurich"
    property string fullName: ""
    property string userName: ""
    property bool userNameTouched: false
    property string password: ""
    property string password2: ""
    property string hostName: facts.id
    property int diskIndex: facts.disks.length === 1 ? 0 : -1
    property bool encrypt: true
    property string passphrase: ""
    property string passphrase2: ""
    property bool hibernation: false
    property bool erase: false

    readonly property var disk: diskIndex >= 0 && diskIndex < facts.disks.length ? facts.disks[diskIndex] : null
    function gib(bytes) { return Math.floor(bytes / 1073741824) }
    readonly property bool hibernationFits: disk !== null && gib(disk.bytes) - facts.ramGib - 1 >= facts.minFreeGib

    function pickLanguage(code) {
        locale = code
        lang = code.startsWith("de") ? "de" : code.startsWith("fr") ? "fr" : code.startsWith("it") ? "it" : "en"
        pickKeyboard(code.startsWith("de_CH") || code.startsWith("it_CH") ? "ch" : code.startsWith("fr_CH") ? "ch-fr"
                     : code.startsWith("de_DE") ? "de" : code.startsWith("en_GB") ? "gb" : "us")
        timeZone = code.startsWith("de_DE") ? "Europe/Berlin" : code.startsWith("en_GB") ? "Europe/London"
                 : code.startsWith("en_US") ? timeZone : "Europe/Zurich"
    }
    function pickKeyboard(code) {
        keyboard = code
        const k = keyboards.find(k => k[0] === code)
        if (k) keyboardChosen(k[2], k[3])
    }

    // lib.sh propose_user_name: "Livio Müller" -> "livio"
    function proposeUserName(name) {
        let first = (name.split(" ")[0] || "").toLowerCase()
        first = first.replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/[éè]/g, "e").replace(/à/g, "a")
        first = first.replace(/[^a-z0-9]/g, "")
        if (!/^[a-z_]/.test(first)) first = "user" + first
        return first.substring(0, 32)
    }
    onFullNameChanged: if (!userNameTouched) userName = proposeUserName(fullName)

    // The same rules as lib.sh; the core checks again
    readonly property bool fullNameOk: fullName.length > 0 && fullName.length <= 64
    readonly property bool userNameOk: /^[a-z_][a-z0-9_-]{0,31}$/.test(userName) && ["root", "nixos", "nobody", facts.id].indexOf(userName) < 0
    readonly property bool hostNameOk: /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(hostName)
    readonly property bool passwordOk: password.length >= 8 && password === password2
    readonly property bool passphraseOk: !encrypt || (passphrase.length >= 8 && passphrase === passphrase2)

    // ---------------------------------------------------------------- pages

    // 0 language, 1 network, 2 time zone, 3 disk, 4 you, 5 summary, 6 installing, 7 done or failed
    property int page: 0
    readonly property var steps: ["s_language", "s_network", "s_timezone", "s_disk", "s_you", "s_summary"]
    readonly property bool installing: page >= 6

    readonly property bool pageOk: [
        true,
        online,
        timeZone !== "",
        disk !== null && passphraseOk,
        fullNameOk && userNameOk && passwordOk && hostNameOk,
        erase,
        false, false
    ][page]

    function go(n) {
        if (installing) return
        page = Math.max(0, Math.min(5, n))
        if (page === 1) checkNetwork()
    }

    // ---------------------------------------------------------------- the installation

    property int step: 0
    property int total: 9
    property var lines: []
    property bool ok: false
    property string error: ""
    property string mokCode: ""
    property bool mokFromDisk: false
    property bool showLog: false

    function install() {
        const answers = {
            hostName: hostName, timeZone: timeZone, locale: locale, keyboard: keyboard,
            user: { name: userName, fullName: fullName },
            disk: disk.stablePath, encrypt: encrypt, hibernation: hibernationFits && hibernation
        }
        step = 0
        lines = []
        error = ""
        page = 6
        backend.call("install", { answers: answers, password: password, passphrase: encrypt ? passphrase : "" }, () => {
            password = password2 = passphrase = passphrase2 = ""
        })
    }

    function load() {
        backend.call("facts", {}, r => root.facts = r)
        backend.call("timezones", {}, r => root.zones = r)
        backend.call("state", {}, s => {
            // A window opened again while or after installing shows where it stands
            if (s.phase === "setup") return
            root.step = s.step
            root.total = s.total
            root.lines = s.lines
            root.error = s.error
            root.mokCode = s.mokCode
            root.mokFromDisk = s.mokFromDisk
            root.ok = s.phase === "done"
            root.page = s.phase === "installing" ? 6 : 7
        })
        checkNetwork()
    }

    function checkNetwork() {
        backend.call("network", {}, r => {
            root.online = r.online
            if (!r.online) scan()
        })
    }
    function scan() {
        scanning = true
        backend.call("wifi.list", {}, r => { root.networks = r; root.scanning = false })
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onEvent(name, data) {
            if (name === "step") { root.step = data.n; root.total = data.total }
            else if (name === "line") root.lines = root.lines.concat([data.text]).slice(-300)
            else if (name === "done") {
                root.ok = data.ok
                root.error = data.error
                root.mokCode = data.mokCode
                root.mokFromDisk = data.mokFromDisk
                root.page = 7
            }
        }
    }

    Timer {
        // While on the network page: is the machine online yet?
        interval: 3000
        repeat: true
        running: root.page === 1 && !root.online
        onTriggered: root.checkNetwork()
    }

    // ---------------------------------------------------------------- layout

    Rectangle { anchors.fill: parent; color: Theme.background }

    // The steps, on the left
    Rectangle {
        id: side
        width: 260
        height: parent.height
        color: Theme.surface
        Rectangle { anchors.right: parent.right; width: Theme.lineHair; height: parent.height; color: Theme.border }

        Column {
            x: Theme.space5
            y: Theme.space6
            width: parent.width - 2 * Theme.space5
            spacing: Theme.space1

            Label { textStyle: "emblem"; text: root.facts.name; color: Theme.text }
            Label { textStyle: "motto"; text: root.t("installer") + "  " + root.facts.version; color: Theme.textMuted }
            Item { width: 1; height: Theme.space6 }

            Repeater {
                model: root.steps
                Item {
                    id: row
                    required property int index
                    required property string modelData
                    readonly property bool current: root.page === index || (index === 5 && root.installing)
                    readonly property bool done: root.page > index
                    width: parent.width
                    height: 34
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusXs
                        color: row.current || (hover.hovered && row.done && !root.installing) ? Theme.surfaceRaised : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    }
                    Rectangle {
                        width: 3; height: parent.height
                        color: Theme.accent
                        opacity: row.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                    }
                    Row {
                        x: Theme.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space3
                        Item {
                            width: 16; height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                anchors.centerIn: parent
                                visible: !row.done || row.current
                                text: row.index + 1
                                textStyle: "caption"
                                color: row.current ? Theme.accentText : Theme.textFaint
                            }
                            Icon { anchors.centerIn: parent; visible: row.done && !row.current; name: "check"; size: 12; color: Theme.success }
                        }
                        Label {
                            text: root.t(row.modelData)
                            textStyle: row.current ? "label" : "body"
                            color: row.current ? Theme.text : row.done ? Theme.textMuted : Theme.textFaint
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: hover; enabled: row.done && !root.installing; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: row.done && !root.installing; onTapped: root.go(row.index) }
                }
            }
        }

        // What the installer found, at the foot
        InfoBlock {
            x: Theme.space4
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.space5
            width: parent.width - 2 * Theme.space4
            model: [
                ["RAM", root.facts.ramGib + " GiB"],
                ["Secure Boot", root.facts.secureBoot ? root.t("v_on") : root.t("v_off")],
                [root.t("s_network"), root.online ? "online" : "offline"]
            ]
        }
    }

    // The page, on the right
    Item {
        id: main
        anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom }

        Column {
            id: head
            x: Theme.space7
            y: Theme.space6
            width: parent.width - 2 * Theme.space7
            spacing: Theme.space2
            Label {
                width: parent.width
                textStyle: "title-lg"
                color: Theme.text
                text: root.page === 0 ? root.tf("g_welcome", root.facts.name)
                    : root.page === 6 ? root.t("s_installing")
                    : root.page === 7 ? (root.ok ? root.t("s_done") : root.t("f_title"))
                    : root.t(root.steps[root.page])
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                text: [root.tf("g_intro", root.facts.name), root.online ? root.t("g_online") : root.t("g_offline"),
                       root.t("q_timezone"), root.tf("q_disk", root.facts.name), "", root.t("q_summary"),
                       "",
                       root.ok ? root.tf("d_title", root.facts.name) : root.error][root.page]
            }
        }

        // Each page in the same frame below the heading
        Item {
            id: body
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top }
            anchors { leftMargin: Theme.space7; rightMargin: Theme.space7; topMargin: Theme.space5; bottomMargin: Theme.space4 }
            clip: true

            // 0: language and keyboard
            Row {
                visible: root.page === 0
                anchors.fill: parent
                spacing: Theme.space6
                Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: Theme.space2
                    Label { textStyle: "micro"; color: Theme.textFaint; text: root.t("s_language").toUpperCase() }
                    Repeater {
                        model: root.languages
                        ListRow {
                            required property var modelData
                            width: parent.width
                            text: modelData[1]
                            selected: root.locale === modelData[0]
                            onClicked: root.pickLanguage(modelData[0])
                        }
                    }
                }
                Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: Theme.space2
                    Label { textStyle: "micro"; color: Theme.textFaint; text: root.t("s_keyboard").toUpperCase() }
                    Repeater {
                        model: root.keyboards
                        ListRow {
                            required property var modelData
                            width: parent.width
                            iconName: "keyboard"
                            text: root.t(modelData[1])
                            selected: root.keyboard === modelData[0]
                            onClicked: root.pickKeyboard(modelData[0])
                        }
                    }
                    Label { width: parent.width; wrapMode: Text.WordWrap; textStyle: "caption"; color: Theme.textFaint; text: root.t("h_keyboard") }
                }
            }

            // 1: network
            Column {
                visible: root.page === 1
                width: parent.width
                spacing: Theme.space3
                Row {
                    visible: root.online
                    spacing: Theme.space2
                    Icon { name: "wifi"; size: 16; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: root.t("g_online"); color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    visible: !root.online
                    width: parent.width
                    Label { textStyle: "micro"; color: Theme.textFaint; text: root.t("g_wifi").toUpperCase(); anchors.verticalCenter: parent.verticalCenter }
                    Item { width: parent.width - 260; height: 1 }
                    Button { small: true; variant: "quiet"; iconName: "refresh-cw"; text: root.t("b_rescan"); loading: root.scanning; onClicked: root.scan() }
                }
                Label { visible: !root.online && !root.scanning && root.networks.length === 0; color: Theme.textMuted; text: root.t("g_no_wifi") }
                ListView {
                    id: nets
                    visible: !root.online
                    width: parent.width
                    height: Math.min(contentHeight, 260)
                    clip: true
                    model: root.networks
                    property int chosen: -1
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        width: nets.width
                        iconName: modelData.secure ? "lock" : "wifi"
                        text: modelData.ssid
                        detail: modelData.signal + "%"
                        selected: nets.chosen === index
                        onClicked: { nets.chosen = index; wifiError.text = "" }
                    }
                }
                Row {
                    visible: !root.online && nets.chosen >= 0
                    spacing: Theme.space3
                    TextField {
                        id: wifiPass
                        visible: nets.chosen >= 0 && root.networks[nets.chosen] && root.networks[nets.chosen].secure
                        width: 280
                        label: root.t("l_password")
                        echoMode: TextInput.Password
                        onAccepted: connect.clicked()
                    }
                    Button {
                        id: connect
                        anchors.bottom: parent.bottom
                        variant: "primary"
                        text: root.t("b_connect")
                        onClicked: {
                            loading = true
                            root.backend.call("wifi.connect", { ssid: root.networks[nets.chosen].ssid, password: wifiPass.text }, r => {
                                connect.loading = false
                                root.online = r.online
                            })
                        }
                    }
                }
                Label { id: wifiError; color: Theme.error; textStyle: "caption"; text: "" }
                Connections {
                    target: root.backend
                    ignoreUnknownSignals: true
                    function onFailed(method, message) {
                        if (method === "wifi.connect") { connect.loading = false; wifiError.text = root.t("e_connect") }
                    }
                }
            }

            // 2: time zone
            Column {
                visible: root.page === 2
                anchors.fill: parent
                spacing: Theme.space3
                SearchField {
                    id: zoneSearch
                    width: 360
                    placeholderText: root.t("ph_search_tz")
                }
                ListView {
                    id: zoneList
                    width: parent.width
                    height: parent.height - zoneSearch.height - parent.spacing
                    clip: true
                    readonly property string q: zoneSearch.text.toLowerCase().replace(/ /g, "_")
                    model: root.zones.filter(z => q === "" || z.toLowerCase().indexOf(q) >= 0)
                    delegate: ListRow {
                        required property string modelData
                        width: zoneList.width
                        iconName: "clock"
                        text: modelData.replace(/_/g, " ").replace("/", "  /  ")
                        selected: root.timeZone === modelData
                        onClicked: root.timeZone = modelData
                    }
                    onVisibleChanged: if (visible) positionViewAtIndex(Math.max(0, model.indexOf(root.timeZone)), ListView.Center)
                }
            }

            // 3: disk, encryption, hibernation
            Column {
                visible: root.page === 3
                width: parent.width
                spacing: Theme.space3
                Label { visible: root.facts.disks.length === 0; color: Theme.error; text: root.t("e_no_disk") }
                Repeater {
                    model: root.facts.disks
                    ListRow {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 36
                        iconName: modelData.transport === "usb" ? "usb" : "hard-drive"
                        text: modelData.path.replace("/dev/", "") + "   " + root.gib(modelData.bytes) + " GiB   " + modelData.model
                        detail: modelData.transport
                        selected: root.diskIndex === index
                        onClicked: root.diskIndex = index
                    }
                }
                Row {
                    spacing: Theme.space2
                    Icon { name: "triangle-alert"; size: 14; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: root.t("h_disk_whole"); color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                }
                Item { width: 1; height: Theme.space3 }
                Switch {
                    text: root.t("q_encrypt")
                    checked: root.encrypt
                    onToggled: root.encrypt = checked
                }
                Label { x: 44; textStyle: "caption"; color: Theme.textFaint; text: root.t("h_encrypt_cost") }
                Row {
                    visible: root.encrypt
                    x: 44
                    spacing: Theme.space4
                    TextField {
                        width: 260
                        label: root.t("l_passphrase")
                        echoMode: TextInput.Password
                        placeholderText: root.t("ph_secret")
                        text: root.passphrase
                        onTextChanged: root.passphrase = text
                        help: root.t("h_passphrase")
                    }
                    TextField {
                        width: 260
                        label: root.t("l_again")
                        echoMode: TextInput.Password
                        text: root.passphrase2
                        onTextChanged: root.passphrase2 = text
                        error: root.passphrase2 !== "" && root.passphrase !== root.passphrase2 ? root.t("e_mismatch")
                             : root.passphrase !== "" && root.passphrase.length < 8 ? root.t("e_short") : ""
                    }
                }
                Item { width: 1; height: Theme.space2 }
                Switch {
                    enabled: root.hibernationFits
                    text: root.t("q_hibernate")
                    checked: root.hibernationFits && root.hibernation
                    onToggled: root.hibernation = checked
                }
                Label {
                    x: 44
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: root.hibernationFits ? root.tf("h_hibernate_cost", root.facts.ramGib + 1) : root.t("g_no_hibernation")
                }
            }

            // 4: you and the computer
            Grid {
                visible: root.page === 4
                columns: 2
                columnSpacing: Theme.space5
                rowSpacing: Theme.space4
                readonly property int w: (body.width - columnSpacing) / 2
                TextField {
                    width: parent.w
                    label: root.t("q_name")
                    placeholderText: "Livio Muster"
                    text: root.fullName
                    onTextChanged: root.fullName = text
                    error: text === "" || root.fullNameOk ? "" : root.t("e_name")
                }
                TextField {
                    width: parent.w
                    label: root.t("q_user")
                    help: root.t("h_user")
                    text: root.userName
                    onTextChanged: if (text !== root.userName) { root.userNameTouched = true; root.userName = text }
                    error: root.userName === "" || root.userNameOk ? "" : root.tf("e_user", root.userName)
                }
                TextField {
                    width: parent.w
                    label: root.t("q_password")
                    echoMode: TextInput.Password
                    placeholderText: root.t("ph_secret")
                    text: root.password
                    onTextChanged: root.password = text
                    error: root.password !== "" && root.password.length < 8 ? root.t("e_short") : ""
                }
                TextField {
                    width: parent.w
                    label: root.t("l_again")
                    echoMode: TextInput.Password
                    text: root.password2
                    onTextChanged: root.password2 = text
                    error: root.password2 !== "" && root.password !== root.password2 ? root.t("e_mismatch") : ""
                }
                TextField {
                    width: parent.w
                    label: root.t("q_computer")
                    text: root.hostName
                    onTextChanged: root.hostName = text
                    error: root.hostNameOk ? "" : root.t("e_computer")
                }
            }

            // 5: summary
            Column {
                visible: root.page === 5
                width: parent.width
                spacing: Theme.space5
                InfoBlock {
                    title: root.facts.name + " " + root.facts.version
                    model: [
                        [root.t("l_language"), (root.languages.find(l => l[0] === root.locale) || ["", root.locale])[1]],
                        [root.t("l_keyboard"), root.t((root.keyboards.find(k => k[0] === root.keyboard) || ["", ""])[1])],
                        [root.t("l_timezone"), root.timeZone],
                        [root.t("l_name"), root.fullName],
                        [root.t("l_user"), root.userName],
                        [root.t("l_computer"), root.hostName],
                        [root.t("l_disk"), root.disk ? root.disk.path.replace("/dev/", "") + ", " + root.gib(root.disk.bytes) + " GiB, " + root.disk.model : ""],
                        [root.t("l_encryption"), root.encrypt ? root.t("v_on") : root.t("v_off")],
                        [root.t("l_hibernation"), root.hibernationFits && root.hibernation ? root.t("v_on") : root.t("v_off")]
                    ]
                }
                Row {
                    visible: root.facts.secureBoot
                    width: parent.width
                    spacing: Theme.space2
                    Icon { id: sbIcon; name: "lock"; size: 14; color: Theme.info; y: 2 }
                    Label { width: parent.width - sbIcon.width - parent.spacing; wrapMode: Text.WordWrap; text: root.tf("g_secure_boot", root.facts.name); color: Theme.textMuted }
                }
                Column {
                    spacing: Theme.space3
                    Row {
                        spacing: Theme.space2
                        Icon { name: "triangle-alert"; size: 14; color: Theme.error; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: root.tf("w_deleted", root.disk ? root.disk.path : ""); color: Theme.error; anchors.verticalCenter: parent.verticalCenter }
                    }
                    CheckBox {
                        text: root.tf("g_erase", root.disk ? root.disk.path : "")
                        checked: root.erase
                        onToggled: root.erase = checked
                    }
                }
            }

            // 6: installing, 7: done or failed
            Column {
                visible: root.page >= 6
                width: parent.width
                spacing: Theme.space4
                ProgressBar {
                    visible: root.page === 6
                    width: parent.width
                    from: 0
                    to: root.total
                    value: Math.max(0, root.step - 0.5)
                    label: root.t("st" + Math.max(1, root.step))
                    valueText: Math.max(1, root.step) + "/" + root.total
                    Behavior on value { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
                Column {
                    visible: root.page === 6
                    spacing: 2
                    Repeater {
                        model: root.total
                        Row {
                            required property int index
                            spacing: Theme.space2
                            readonly property int n: index + 1
                            Item {
                                width: 16; height: 18
                                Icon { anchors.centerIn: parent; visible: n < root.step; name: "check"; size: 12; color: Theme.success }
                                Label { anchors.centerIn: parent; visible: n === root.step; text: ">"; textStyle: "label"; color: Theme.accentText }
                            }
                            Label {
                                text: root.t("st" + n)
                                color: n === root.step ? Theme.text : n < root.step ? Theme.textMuted : Theme.textFaint
                            }
                        }
                    }
                }

                // Done: what comes at the next start
                Column {
                    visible: root.page === 7 && root.ok
                    width: parent.width
                    spacing: Theme.space3
                    Label { width: parent.width; wrapMode: Text.WordWrap; color: Theme.text; text: root.t("d_remove") }
                    Label { visible: root.encrypt; width: parent.width; wrapMode: Text.WordWrap; color: Theme.textMuted; text: root.t("d_passphrase") }
                    Column {
                        visible: root.mokCode !== "" || root.mokFromDisk
                        width: parent.width
                        spacing: Theme.space2
                        Item { width: 1; height: Theme.space2 }
                        Label { width: parent.width; wrapMode: Text.WordWrap; color: Theme.text; text: root.t("d_mok") }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.textMuted
                            text: root.mokCode !== "" ? root.t("d_mok_steps") : root.tf("d_mok_disk", root.facts.id)
                        }
                        Row {
                            visible: root.mokCode !== ""
                            spacing: Theme.space3
                            Label { text: root.t("d_mok_code"); color: Theme.textMuted; anchors.baseline: code.baseline }
                            Label { id: code; text: root.mokCode; font.family: Theme.mono; font.pixelSize: 40; font.weight: Font.Light; color: Theme.accentText }
                        }
                    }
                }

                // Failed: the error is under the heading; the disk may be half written
                Label {
                    visible: root.page === 7 && !root.ok
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    text: root.t("f_text")
                }

                Button {
                    variant: "quiet"
                    small: true
                    iconName: root.showLog ? "eye-off" : "eye"
                    text: root.showLog ? root.t("g_log_hide") : root.t("g_log_show")
                    onClicked: root.showLog = !root.showLog
                }
                Rectangle {
                    visible: root.showLog
                    width: parent.width
                    height: 180
                    color: Theme.surfaceSunken
                    border.color: Theme.border
                    radius: Theme.radiusSm
                    clip: true
                    Label {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.space2 }
                        textStyle: "caption"
                        color: Theme.textMuted
                        wrapMode: Text.WrapAnywhere
                        text: root.lines.slice(-10).join("\n")
                    }
                }
            }
        }

        // Back and Next
        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 72
            Rectangle { width: parent.width; height: Theme.lineHair; color: Theme.border }
            Row {
                anchors { left: parent.left; leftMargin: Theme.space7; verticalCenter: parent.verticalCenter }
                spacing: Theme.space3
                Button {
                    visible: root.page > 0 && root.page < 6
                    variant: "quiet"
                    iconName: "chevron-left"
                    text: root.t("b_back")
                    onClicked: root.go(root.page - 1)
                }
                Button {
                    visible: root.page === 7 && !root.ok
                    variant: "quiet"
                    iconName: "chevron-left"
                    text: root.t("b_retry")
                    onClicked: { root.page = 5; root.erase = false }
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: Theme.space7; verticalCenter: parent.verticalCenter }
                spacing: Theme.space3
                Button {
                    visible: root.page === 7 && root.ok
                    variant: "quiet"
                    text: root.t("b_stay")
                    onClicked: root.closeRequested()
                }
                Button {
                    visible: root.page === 7 && root.ok
                    variant: "primary"
                    iconName: "power"
                    text: root.t("b_restart")
                    onClicked: root.backend.call("reboot", {}, () => {})
                }
                Button {
                    visible: root.page < 5
                    variant: "primary"
                    enabled: root.pageOk
                    text: root.t("b_next")
                    iconName: "arrow-right"
                    onClicked: root.go(root.page + 1)
                }
                Button {
                    visible: root.page === 5
                    variant: "danger"
                    enabled: root.pageOk
                    text: root.t("b_install")
                    iconName: "hard-drive-download"
                    onClicked: root.install()
                }
            }
        }
    }

    Component.onCompleted: if (backend) load()
}
