// The graphical installer in the live session of the ISO: the window (Installer.qml) and, while it
// is closed, a card on the desktop that opens it again. Installed as /etc/xdg/quickshell/strix-installer
// and started by the user service strix-installer-ui as soon as the session is there:
//   qs -c strix-installer
// The search's "Install Strix" entry and `qs -c strix-installer ipc call installer open` open it too.
// The back end (backend.py) answers on $XDG_RUNTIME_DIR/strix/install.sock.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Strix
import Strix.Shell

ShellRoot {
    id: root

    /// The window is up. Closing it only hides it; the answers and a running installation stay.
    property bool open: true

    // The colors of the session's theme, the same as the rest of the desktop
    ThemeFile {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/strix/theme/tokens.json"
    }

    Backend {
        id: install
        service: "install"
        onConnectedChanged: if (connected) ui.load()
    }

    IpcHandler {
        target: "installer"
        function open(): void { root.open = true }
        function close(): void { root.open = false }
        function isOpen(): bool { return root.open }
    }

    FloatingWindow {
        id: window
        visible: root.open
        // Fixed, the window rule of the live session (iso/live.nix) finds it by this
        title: "Installer"
        implicitWidth: 1040
        implicitHeight: 700
        color: Theme.background
        onVisibleChanged: if (!visible) root.open = false

        Installer {
            id: ui
            anchors.fill: parent
            backend: install
            onCloseRequested: root.open = false
            // The session types with the chosen keyboard at once: the live user's own Hyprland
            // file (read last by hyprland.lua), then a reload
            onKeyboardChosen: (layout, variant) => Quickshell.execDetached(["sh", "-c",
                'mkdir -p "$HOME/.config/strix" && printf \'hl.config({ input = { kb_layout = "%s", kb_variant = "%s" } })\\n\' "$1" "$2" > "$HOME/.config/strix/hyprland.lua" && hyprctl reload',
                "sh", layout, variant])
        }
    }

    // While the window is closed: in the middle of the desktop, under every window, a card that
    // says what this is and opens the installer again
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: !root.open
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "strix-installer-launcher"
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: 460
            implicitHeight: card.implicitHeight

            Surface {
                id: card
                width: parent.width
                implicitHeight: col.implicitHeight + 2 * Theme.space5
                elevation: "panel"

                Column {
                    id: col
                    x: Theme.space5
                    y: Theme.space5
                    width: parent.width - 2 * Theme.space5
                    spacing: Theme.space3

                    Label { textStyle: "emblem"; text: ui.facts.name; color: Theme.text }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.textMuted
                        text: ui.installing && ui.page === 6 ? ui.tf("g_running", Math.round(100 * Math.max(0, ui.step - 1) / ui.total))
                            : ui.page === 7 ? (ui.ok ? ui.tf("d_title", ui.facts.name) : ui.t("f_title"))
                            : ui.t("g_reopen")
                    }
                    ProgressBar {
                        visible: ui.page === 6
                        width: parent.width
                        from: 0
                        to: ui.total
                        value: Math.max(0, ui.step - 0.5)
                    }
                    Item { width: 1; height: Theme.space1 }
                    Button {
                        variant: "primary"
                        iconName: "hard-drive-download"
                        text: ui.tf("b_reopen", ui.facts.name)
                        onClicked: root.open = true
                    }
                }
            }
        }
    }
}
