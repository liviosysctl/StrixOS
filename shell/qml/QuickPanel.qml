// The frame of a quick panel: what drops out of the bar or grows out of the dock when one of
// their buttons is clicked. A title, a control at its right (usually the switch) and the rows.
// The rows stand one step of the grid inside the plate, the title in line with their symbols.
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
    height: list.y + list.implicitHeight + Theme.space2

    Label {
        x: 2 * Theme.space2
        y: Theme.space2
        height: Theme.control
        textStyle: "heading"
        text: root.title
    }
    Item {
        id: cornerBox
        anchors.right: parent.right
        anchors.rightMargin: 2 * Theme.space2
        y: Theme.space2 + (Theme.control - height) / 2
        width: childrenRect.width
        height: childrenRect.height
    }
    Column {
        id: list
        x: Theme.space2
        y: Theme.space2 + Theme.control
        width: parent.width - 2 * Theme.space2
    }
}
