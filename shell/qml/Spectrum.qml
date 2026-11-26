// The sound as bars (cava), for the Visualizer of StrixUI: on the desktop under the clock and in
// the media player of the dock. cava runs only while something plays and one of them is shown;
// it reads from PipeWire, the config is /etc/xdg/strix/cava.conf (modules/desktop/shell.nix).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    /// Numbers from 0 to 1, one per bar
    property var values: []
    /// The clock of the desktop shows the bars, on a screen without windows
    readonly property bool forDesktop: Desktop.clock && Hyprland.monitors.values.some(m =>
        !m.activeWorkspace || m.activeWorkspace.toplevels.values.length === 0)
    /// The media player of the dock is open
    property bool forDock: false
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool running: root.playing && (root.forDesktop || root.forDock)

    onRunningChanged: if (!running) root.values = []

    Process {
        command: ["cava", "-p", "/etc/xdg/strix/cava.conf"]
        running: root.running
        stdout: SplitParser {
            onRead: line => root.values = line.split(";").filter(v => v !== "").map(v => Number(v) / 100)
        }
    }
}
