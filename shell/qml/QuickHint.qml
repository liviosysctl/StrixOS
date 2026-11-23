// A quiet line in a quick panel: why the list is empty
import QtQuick
import Strix

Label {
    x: Theme.space2
    width: parent.width - 2 * Theme.space2
    height: Theme.control
    verticalAlignment: Text.AlignVCenter
    textStyle: "caption"
    color: Theme.textFaint
    wrapMode: Text.WordWrap
}
