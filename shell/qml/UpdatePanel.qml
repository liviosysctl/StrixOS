// A newer version in a quick panel: what changed since the one installed (the first lines of the
// commits, newest first) and the way to install it. The bar shows its mark only while
// strix-update-check has found one.
import QtQuick
import Quickshell
import Strix

QuickPanel {
    id: root

    /// update.json of strix-update-check: available, rev, changes
    property var update: null
    readonly property var changes: (root.update && root.update.changes) || []

    /// The update was started: the panel closes
    signal done()

    title: "Update"
    width: 340
    corner: Label {
        textStyle: "caption"
        color: Theme.textMuted
        text: root.changes.length === 1 ? "1 change" : root.changes.length + " changes"
        visible: root.changes.length > 0
    }

    QuickHint {
        visible: root.changes.length === 0
        text: "A newer version is ready"
    }
    Repeater {
        model: root.changes.slice(0, 8)
        Label {
            required property string modelData
            x: Theme.space2
            width: parent.width - 2 * Theme.space2
            height: Theme.space5
            verticalAlignment: Text.AlignVCenter
            textStyle: "caption"
            color: Theme.textMuted
            elide: Text.ElideRight
            text: modelData
        }
    }
    QuickHint {
        visible: root.changes.length > 8
        text: "and " + (root.changes.length - 8) + " more"
    }
    ListRow {
        width: parent.width
        iconName: "download"
        text: "Update now"
        onClicked: {
            root.done()
            // In its own scope, so it outlives the restart of the shell that ends the update
            Quickshell.execDetached(["uwsm", "app", "--", "ghostty", "--title=Update", "--wait-after-command=true", "-e", "sh", "-c",
                "sudo strix-update; systemctl --user start strix-update-check.service"])
        }
    }
}
