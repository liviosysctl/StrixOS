// The installer with the mock back end, for preview.py. Setting `script` runs it with `ui` and `mock`.
import QtQuick
import Strix

Item {
    id: top
    width: 1040
    height: 700
    property string script: ""
    onScriptChanged: if (script !== "") new Function("ui", "mock", script)(ui, mock)

    MockBackend { id: mock }
    Installer {
        id: ui
        anchors.fill: parent
        backend: mock
    }
}
