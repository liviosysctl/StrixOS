// The Store (the school proof of concept): apps from nixpkgs, installed or removed with one click.
// The service strix-store (Backend "store") holds the package index and the catalog
// (shell/store.toml): its first page suggests apps and shows every category, the list on the left
// leads to a category or to what is installed, the search above finds any package. A package
// opens on its own page. Icons come from the service (Papirus, then the apps' own); without one a
// letter stands in. What the system brings along (Zen, Ghostty, Files...) is marked as built in
// and is neither installed nor removed here.
// Installing runs strix-apps, which writes apps.json and rebuilds; its output streams into the
// well at the bottom. Proprietary apps are marked; installing one asks first (Q7), and the
// service refuses it otherwise. strix-shell opens a package in a shell in Ghostty, as nix-shell -p
// does: to try it, nothing is installed.
// Opened from Search (Apps › Store) or with `qs -c strix ipc call store open`.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    /// home, installed, a category's id, or app (one package, root.app)
    property string page: "home"
    /// The page the app page leads back to
    property string back: "home"
    property var app: null
    /// The first page from the service: ready, count, featured, categories
    property var home: ({ ready: true, count: 0, featured: [], categories: [] })
    /// store: installed from here, system: the apps the system brings along
    property var installed: ({ store: [], system: [] })
    property var results: []
    property int selected: 0
    /// The running or last job: action, attr, running, ok, lines
    property var job: null
    property var lines: []
    property string error: ""

    readonly property bool searching: input.text.trim() !== ""
    readonly property bool busy: !!(root.job && root.job.running)
    readonly property var category: root.home.categories.find(c => c.id === root.page) || null
    readonly property int sidebar: 220

    function show(text) {
        root.error = ""
        root.open = true
        root.page = "home"
        root.app = null
        input.text = text || ""
        root.load()
        store.call("job", {}, j => { if (j) { root.job = j; root.lines = j.lines || [] } })
        if (text) {
            // From Search: the package itself when it is found by its attribute
            store.call("search", { text: text, limit: 5 }, r => {
                const exact = ((r && r.results) || []).find(p => p.attr === text)
                if (exact) root.openApp(exact)
            })
        }
    }

    function load() {
        store.call("home", {}, r => { if (r) root.home = r })
        store.call("installed", {}, r => { if (r) root.installed = r })
        if (root.searching) root.refresh()
    }

    function refresh() {
        store.call("search", { text: input.text, limit: 60 }, r => {
            root.results = (r && r.results) || []
            root.selected = 0
        })
    }

    function go(page) {
        input.text = ""
        root.app = null
        root.page = page
        pages.contentY = 0
    }

    function openApp(pkg) {
        if (!pkg) return
        if (root.page !== "app") root.back = root.searching ? "search" : root.page
        root.app = pkg
        root.page = "app"
        pages.contentY = 0
    }

    function leaveApp() {
        root.app = null
        root.page = root.back === "search" ? "home" : root.back
    }

    /// The package's card again after a job, so the app page shows what is now true
    function reloadApp() {
        if (!root.app) return
        const attr = root.app.attr
        store.call("search", { text: attr, limit: 5 }, r => {
            const card = ((r && r.results) || []).find(p => p.attr === attr)
            if (card && root.app && root.app.attr === attr) root.app = card
        })
    }

    // The package waiting for an answer to the question about proprietary software, and whether
    // it is for a shell instead of an install
    property var asking: null
    property bool askingShell: false

    function act(pkg) {
        if (!pkg || pkg.builtIn || root.busy) return
        if (!pkg.installed && pkg.unfree) {
            root.asking = pkg
            root.askingShell = false
            proprietary.open()
            return
        }
        root.run(pkg, false)
    }

    /// The package in a shell in a new terminal, nothing installed
    function shell(pkg, agreed) {
        if (!pkg) return
        if (pkg.unfree && !agreed) {
            root.asking = pkg
            root.askingShell = true
            proprietary.open()
            return
        }
        const args = ["strix-shell"].concat(pkg.unfree ? ["--proprietary"] : []).concat([pkg.attr])
        Quickshell.execDetached(["uwsm", "app", "--", "ghostty", "-e"].concat(args))
    }

    function run(pkg, agreed) {
        root.error = ""
        root.lines = []
        const action = pkg.installed ? "remove" : "install"
        const params = { attr: pkg.attr }
        if (agreed) params.proprietary = true
        store.call(action, params, () => {
            root.job = { action: action, attr: pkg.attr, name: pkg.name, running: true, lines: [] }
        })
    }

    function jobText() {
        if (root.error !== "") return root.error
        if (!root.job) return ""
        const name = root.job.name || root.job.attr
        if (root.job.running) return (root.job.action === "install" ? "Installing " : "Removing ") + name + "..."
        return (root.job.action === "install" ? "Installed " : "Removed ") + name
    }

    Backend {
        id: store
        service: "store"
        onEvent: (name, data) => {
            if (name === "progress") {
                root.lines = root.lines.concat([data.line]).slice(-200)
            } else if (name === "done") {
                const label = root.job && root.job.attr === data.attr ? root.job.name : data.attr
                root.job = Object.assign({ name: label }, data, { running: false })
                if (!data.ok) root.error = (data.action === "install" ? "Installing " : "Removing ") + label + " failed"
                root.load()
                root.reloadApp()
            }
        }
        onFailed: (method, message) => root.error = message
    }

    IpcHandler {
        target: "store"
        function open(): void { root.show("") }
        function find(text: string): void { root.show(text) }
        function close(): void { root.open = false }
        function isOpen(): bool { return root.open }
        function busy(): bool { return root.busy }
    }

    // ---------------------------------------------------------------- parts

    /// The icon of a package, or its first letter on a plate of the accent
    component AppIcon: Item {
        id: appIcon
        property var pkg: null
        property int size: 44
        width: size
        height: size

        Image {
            id: picture
            anchors.fill: parent
            visible: status === Image.Ready
            source: appIcon.pkg && appIcon.pkg.icon ? "file://" + appIcon.pkg.icon : ""
            sourceSize: Qt.size(appIcon.size * 2, appIcon.size * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }
        Rectangle {
            anchors.fill: parent
            visible: picture.status !== Image.Ready
            radius: Math.round(appIcon.size / 4)
            color: Theme.alpha(Theme.accent, 0.22)
            border.width: Theme.lineHair
            border.color: Theme.alpha(Theme.accent, 0.5)
            Label {
                anchors.centerIn: parent
                textStyle: appIcon.size >= 64 ? "title-lg" : "subtitle"
                color: Theme.text
                text: appIcon.pkg ? (appIcon.pkg.name || appIcon.pkg.pname || "?").charAt(0).toUpperCase() : ""
            }
        }
    }

    /// Where a package stands: built in, installed, proprietary
    component Marks: Row {
        id: marks
        property var pkg: null
        spacing: Theme.space1
        Badge { visible: !!(marks.pkg && marks.pkg.builtIn); text: "Built in" }
        Badge { visible: !!(marks.pkg && marks.pkg.installed && !marks.pkg.builtIn); text: "Installed"; kind: "accent" }
        Badge { visible: !!(marks.pkg && marks.pkg.unfree); text: "Proprietary" }
    }

    /// Install or Remove; nothing for what the system brings along
    component Action: Button {
        property var pkg: null
        visible: !!pkg && !pkg.builtIn
        /// The page of the app has the strong button; tiles and rows a quiet one each
        property bool strong: false
        variant: pkg && pkg.installed ? "danger" : strong ? "primary" : "default"
        text: pkg && pkg.installed ? "Remove" : "Install"
        loading: !!(pkg && root.busy && root.job.attr === pkg.attr)
        enabled: !root.busy
        onClicked: root.act(pkg)
    }

    /// An app on the first page and in a category: a well in the glass that opens its page
    component AppTile: Rectangle {
        id: tile
        property var pkg: null
        height: 116
        radius: Theme.radiusMd
        color: hover.hovered ? Theme.alpha(Theme.text, 0.07) : Theme.alpha(Theme.text, 0.04)
        border.width: Theme.lineHair
        border.color: hover.hovered ? Theme.borderStrong : Theme.glassEdge

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openApp(tile.pkg) }

        AppIcon {
            id: tileIcon
            x: Theme.space3
            y: Theme.space3
            pkg: tile.pkg
        }
        Column {
            anchors { left: tileIcon.right; leftMargin: Theme.space3; right: parent.right; rightMargin: Theme.space3; top: parent.top; topMargin: Theme.space3 }
            spacing: 2
            Label {
                width: parent.width
                elide: Text.ElideRight
                textStyle: "label"
                color: Theme.text
                text: tile.pkg ? tile.pkg.name : ""
            }
            Label {
                width: parent.width
                height: 2 * 16
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                textStyle: "caption"
                color: Theme.textMuted
                text: tile.pkg ? (tile.pkg.description || tile.pkg.attr) : ""
            }
        }
        Marks {
            anchors { left: parent.left; leftMargin: Theme.space3; bottom: parent.bottom; bottomMargin: Theme.space3 + (Theme.control - Theme.mark) / 2 }
            pkg: tile.pkg
        }
        Action {
            anchors { right: parent.right; rightMargin: Theme.space3; bottom: parent.bottom; bottomMargin: Theme.space3 }
            pkg: tile.pkg
        }
    }

    /// Tiles three in a row
    component Tiles: Grid {
        id: grid
        property var apps: []
        columns: 3
        spacing: Theme.space3
        Repeater {
            model: grid.apps
            AppTile {
                required property var modelData
                width: (grid.width - 2 * grid.spacing) / 3
                pkg: modelData
            }
        }
    }

    /// A package in a list: the search, what is installed
    component AppRow: Item {
        id: row
        property var pkg: null
        property bool chosen: false
        height: 56

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: row.chosen || rowHover.hovered ? Theme.surfaceRaised : "transparent"
            Rectangle {
                visible: row.chosen
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.lineBold
                height: Theme.icon
                radius: width / 2
                color: Theme.accent
            }
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openApp(row.pkg) }

        AppIcon {
            id: rowIcon
            x: Theme.space3
            anchors.verticalCenter: parent.verticalCenter
            size: 36
            pkg: row.pkg
        }
        Column {
            anchors { left: rowIcon.right; leftMargin: Theme.space3; right: rowAction.left; rightMargin: Theme.space3; verticalCenter: parent.verticalCenter }
            Row {
                spacing: Theme.space2
                Label { textStyle: "label"; color: Theme.text; text: row.pkg ? row.pkg.name : "" }
                Label { textStyle: "caption"; color: Theme.textFaint; text: row.pkg ? row.pkg.version : "" }
                Marks { pkg: row.pkg; anchors.verticalCenter: parent.verticalCenter }
            }
            Label {
                width: parent.width
                elide: Text.ElideRight
                textStyle: "caption"
                color: Theme.textMuted
                text: row.pkg ? (row.pkg.description || row.pkg.attr) : ""
            }
        }
        Action {
            id: rowAction
            anchors { right: parent.right; rightMargin: Theme.space2; verticalCenter: parent.verticalCenter }
            pkg: row.pkg
        }
    }

    /// The name of a part of a page, with a way to all of it
    component Heading: Item {
        id: heading
        property string title
        property string about
        property string more: ""
        width: parent ? parent.width : 0
        height: Theme.control
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space3
            Label { textStyle: "subtitle"; color: Theme.text; text: heading.title }
            // On the line of the title
            Label { textStyle: "caption"; color: Theme.textFaint; text: heading.about; topPadding: 6 }
        }
        Button {
            visible: heading.more !== ""
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            variant: "quiet"
            text: "See all"
            iconName: "chevron-right"
            onClicked: root.go(heading.more)
        }
    }

    // ---------------------------------------------------------------- the window

    FloatingWindow {
        visible: root.open
        title: "Store"
        implicitWidth: 1080
        implicitHeight: 720
        // Smoked glass: the compositor blurs what lies behind the window
        color: Theme.smoke(Theme.surface)
        onVisibleChanged: if (!visible) root.open = false

        Row {
            anchors.fill: parent

            // The ways through the Store: the first page, what is installed, the categories
            Rectangle {
                width: root.sidebar
                height: parent.height
                // A well in the glass of the window, as in Settings
                color: Theme.alpha(Theme.text, 0.04)
                Column {
                    anchors { fill: parent; margins: Theme.space2 }
                    spacing: Theme.space1
                    Label {
                        x: Theme.space2
                        textStyle: "title"
                        color: Theme.text
                        text: "Store"
                        bottomPadding: Theme.space2
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.go("home") }
                    }
                    ListRow {
                        width: parent.width
                        text: "Discover"
                        iconName: "layout-grid"
                        selected: !root.searching && (root.page === "home" || (root.page === "app" && root.back === "home"))
                        onClicked: root.go("home")
                    }
                    ListRow {
                        width: parent.width
                        text: "Installed"
                        iconName: "package"
                        detail: root.installed.store.length > 0 ? String(root.installed.store.length) : ""
                        selected: !root.searching && (root.page === "installed" || (root.page === "app" && root.back === "installed"))
                        onClicked: root.go("installed")
                    }
                    Label {
                        x: Theme.space2
                        topPadding: Theme.space4
                        bottomPadding: Theme.space1
                        textStyle: "caption"
                        color: Theme.textMuted
                        text: "Categories"
                    }
                    Repeater {
                        model: root.home.categories
                        ListRow {
                            required property var modelData
                            width: parent.width
                            text: modelData.name
                            iconName: modelData.symbol
                            selected: !root.searching && (root.page === modelData.id || (root.page === "app" && root.back === modelData.id))
                            onClicked: root.go(modelData.id)
                        }
                    }
                }
            }

            Item {
                width: parent.width - root.sidebar
                height: parent.height

                SearchField {
                    id: input
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space5 }
                    placeholderText: root.home.ready && root.home.count > 0
                        ? "Find an app among " + root.home.count.toLocaleString(Qt.locale(), "f", 0)
                        : "Find an app"
                    onTextChanged: {
                        if (root.page === "app" && text !== "") root.page = root.back === "search" ? "home" : root.back
                        searchLater.restart()
                    }
                    onAccepted: if (root.searching) root.openApp(root.results[root.selected])
                    Timer { id: searchLater; interval: 150; onTriggered: if (root.searching) root.refresh() }
                }

                // ------------------------------------------------ the search
                ListView {
                    id: list
                    visible: root.searching && root.page !== "app"
                    anchors { left: parent.left; right: parent.right; top: input.bottom; bottom: log.top; leftMargin: Theme.space5; rightMargin: Theme.space5; topMargin: Theme.space3; bottomMargin: Theme.space3 }
                    clip: true
                    spacing: Theme.space1
                    model: root.results
                    currentIndex: root.selected
                    delegate: AppRow {
                        required property var modelData
                        required property int index
                        width: list.width
                        pkg: modelData
                        chosen: index === root.selected
                    }
                    Label {
                        visible: root.searching && root.results.length === 0
                        textStyle: "body"
                        color: Theme.textFaint
                        text: "Nothing in nixpkgs fits \"" + input.text.trim() + "\"."
                    }
                }

                // ------------------------------------------------ the pages
                Flickable {
                    id: pages
                    visible: !list.visible
                    anchors { left: parent.left; right: parent.right; top: input.bottom; bottom: log.top; topMargin: Theme.space3; bottomMargin: Theme.space3 }
                    contentHeight: content.implicitHeight + Theme.space5
                    clip: true

                    Column {
                        id: content
                        x: Theme.space5
                        width: pages.width - 2 * Theme.space5
                        spacing: Theme.space5

                        Label {
                            visible: !root.home.ready
                            width: parent.width
                            wrapMode: Text.WordWrap
                            textStyle: "body"
                            color: Theme.textMuted
                            text: "The list of apps is still being fetched. It comes once after the installation and after each update."
                        }

                        // The first page: suggestions, then a taste of every category
                        Column {
                            visible: root.page === "home" && root.home.ready
                            width: parent.width
                            spacing: Theme.space5

                            Column {
                                width: parent.width
                                spacing: Theme.space2
                                Heading { title: "Suggestions"; about: "Free apps worth having" }
                                Tiles { width: parent.width; apps: root.home.featured.filter(p => !p.installed).slice(0, 6) }
                            }
                            Repeater {
                                model: root.home.categories
                                Column {
                                    required property var modelData
                                    width: content.width
                                    spacing: Theme.space2
                                    Heading { title: modelData.name; about: modelData.about; more: modelData.apps.length > 3 ? modelData.id : "" }
                                    Tiles { width: parent.width; apps: modelData.apps.slice(0, 3) }
                                }
                            }
                        }

                        // A category: all its apps
                        Column {
                            visible: root.category !== null
                            width: parent.width
                            spacing: Theme.space3
                            Column {
                                spacing: Theme.space1
                                Label { textStyle: "title"; color: Theme.text; text: root.category ? root.category.name : "" }
                                Label { textStyle: "caption"; color: Theme.textFaint; text: root.category ? root.category.about : "" }
                            }
                            Tiles { width: parent.width; apps: root.category ? root.category.apps : [] }
                            Label {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                textStyle: "caption"
                                color: Theme.textFaint
                                text: "A choice. The search above finds every app in nixpkgs."
                            }
                        }

                        // What is installed from here, then what the system brings along
                        Column {
                            visible: root.page === "installed"
                            width: parent.width
                            spacing: Theme.space2
                            Label { textStyle: "title"; color: Theme.text; text: "Installed" }
                            Label {
                                visible: root.installed.store.length === 0
                                textStyle: "body"
                                color: Theme.textFaint
                                text: "Nothing installed from the Store yet."
                            }
                            Repeater {
                                model: root.installed.store
                                AppRow { required property var modelData; width: content.width; pkg: modelData }
                            }
                            Heading { visible: root.installed.system.length > 0; title: "Built in"; about: "Comes with Strix and stays" }
                            Repeater {
                                model: root.installed.system
                                AppRow { required property var modelData; width: content.width; pkg: modelData }
                            }
                        }

                        // One package
                        Column {
                            visible: root.page === "app" && root.app !== null
                            width: parent.width
                            spacing: Theme.space4

                            Button {
                                variant: "quiet"
                                iconName: "chevron-left"
                                text: "Back"
                                onClicked: root.leaveApp()
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.space5
                                AppIcon { size: 96; pkg: root.app }
                                Column {
                                    width: parent.width - 96 - Theme.space5
                                    spacing: Theme.space2
                                    Label { textStyle: "title-lg"; color: Theme.text; text: root.app ? root.app.name : "" }
                                    Row {
                                        spacing: Theme.space2
                                        Label { textStyle: "caption"; color: Theme.textMuted; text: root.app ? root.app.version : "" }
                                        Label { textStyle: "code"; color: Theme.textFaint; text: root.app ? root.app.attr : "" }
                                        Marks { pkg: root.app; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    Row {
                                        topPadding: Theme.space2
                                        spacing: Theme.space2
                                        Action { pkg: root.app; strong: true }
                                        Button {
                                            visible: !!root.app && !root.app.builtIn
                                            text: "Try it in a shell"
                                            iconName: "square-terminal"
                                            onClicked: root.shell(root.app, false)
                                        }
                                        Label {
                                            visible: !!root.app && root.app.builtIn
                                            textStyle: "body"
                                            color: Theme.textMuted
                                            text: "Comes with Strix: it is part of the system and stays."
                                        }
                                    }
                                }
                            }

                            Rule { width: parent.width }

                            Label {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                textStyle: "body"
                                color: Theme.text
                                text: root.app ? (root.app.description || "No description in nixpkgs.") : ""
                            }
                            Label {
                                visible: !!(root.app && root.app.homepage)
                                textStyle: "body"
                                textFormat: Text.StyledText
                                color: Theme.textMuted
                                linkColor: Theme.accentText
                                text: root.app && root.app.homepage ? "<a href=\"" + root.app.homepage + "\">" + root.app.homepage + "</a>" : ""
                                onLinkActivated: link => Qt.openUrlExternally(link)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            Label {
                                visible: !!(root.app && root.app.unfree)
                                width: parent.width
                                wrapMode: Text.WordWrap
                                textStyle: "caption"
                                color: Theme.textFaint
                                text: "Not open source: its code is not public, and its licence may limit what you can do with it."
                            }
                        }
                    }
                }

                // What strix-apps says while it rebuilds, in a well in the glass of the window
                Rectangle {
                    id: log
                    visible: root.job !== null
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.space5 }
                    height: visible ? 150 : 0
                    radius: Theme.radiusMd
                    color: Theme.alpha(Theme.text, 0.04)
                    border.color: Theme.glassEdge

                    Column {
                        anchors { fill: parent; margins: Theme.space3 }
                        spacing: Theme.space1
                        Label {
                            textStyle: "label"
                            color: root.error !== "" ? Theme.error : Theme.text
                            text: root.jobText()
                        }
                        ProgressBar {
                            visible: root.busy
                            width: parent.width
                            indeterminate: true
                        }
                        ListView {
                            id: output
                            width: parent.width
                            height: parent.height - y
                            clip: true
                            model: root.lines
                            onCountChanged: positionViewAtEnd()
                            delegate: Label {
                                required property string modelData
                                width: output.width
                                elide: Text.ElideRight
                                textStyle: "code"
                                color: Theme.textMuted
                                text: modelData
                            }
                        }
                    }
                }
            }
        }

        Dialog {
            id: proprietary
            title: root.asking ? (root.askingShell ? "Open " : "Install ") + root.asking.name + "?" : ""
            text: root.askingShell
                ? "This app is not open source: its code is not public, and its licence may limit what you can do with it. The shell only fetches it, nothing is installed."
                : "This app is not open source: its code is not public, and its licence may limit what you can do with it. It installs like any other app and can be removed again."
            acceptText: root.askingShell ? "Open anyway" : "Install anyway"
            onAccepted: {
                if (root.asking) {
                    if (root.askingShell) root.shell(root.asking, true)
                    else root.run(root.asking, true)
                }
                root.asking = null
            }
            onRejected: root.asking = null
        }

        Shortcut { sequence: "Down"; enabled: root.open && root.searching && !proprietary.visible; onActivated: root.selected = Math.min(root.selected + 1, root.results.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open && root.searching && !proprietary.visible; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut {
            sequence: "Escape"
            enabled: root.open && !proprietary.visible
            onActivated: {
                if (root.page === "app") root.leaveApp()
                else if (input.text !== "") input.text = ""
                else if (root.page !== "home") root.go("home")
                else root.open = false
            }
        }
    }
}
