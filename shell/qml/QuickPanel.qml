// The frame of a quick panel: what drops out of the bar or grows out of the dock when one of
// their symbols is clicked. A title, a control at its right (usually the switch) and the rows.
// The panels themselves are WifiPanel, BluetoothPanel, SoundPanel, PowerPanel and SessionPanel.
import QtQuick
import Strix

Surface {
    id: root

    property string title
    default property alias rows: list.data
    /// The control at the right of the title: the switch
    property alias corner: cornerBox.data

    /// Opens a page of Settings and closes the panel
    signal settings(string page)

    elevation: "panel"
    width: 280
    height: list.y + list.implicitHeight + Theme.space3

    Label { x: Theme.space4; y: Theme.space3; textStyle: "heading"; color: Theme.text; text: root.title }
    Item {
        id: cornerBox
        anchors.right: parent.right
        anchors.rightMargin: Theme.space4
        y: Theme.space3 + 1
        width: childrenRect.width
        height: childrenRect.height
    }
    Column {
        id: list
        x: Theme.space2
        y: Theme.space3 + 20 + Theme.space2
        width: parent.width - 2 * Theme.space2
    }
}
