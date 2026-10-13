// Host temporário para testes visuais. Nunca usa configuração real do usuário.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin" as Holdings

ShellRoot {
    QtObject {
        id: hostBar
        property string position: "top"
        property bool vertical: false
        property int barSize: 26
        property color foreground: Color.foreground
        property color barForeground: Color.foreground
        property color background: Color.background
        property color urgent: Color.urgent
        property string fontFamily: Style.font.family
        property var activePopout: null
        property var clickTargets: []
        property bool foregroundAnimationEnabled: false
        function requestPopout(owner) { activePopout = owner }
        function releasePopout(owner) { activePopout = null }
        function showTooltip(target, text) {}
        function hideTooltip(target) {}
    }
    PanelWindow {
        id: window
        anchors { top: true; left: true; right: true }
        implicitHeight: 26
        color: Color.background
        Text {
            anchors.centerIn: parent
            text: "TESTE VISUAL · quantidade fictícia de 0,01 BTC · configuração isolada"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: 12
        }
        Holdings.BarWidget {
            id: widget
            bar: hostBar
            anchors.right: parent.right
            anchors.rightMargin: 12
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: if (widget.loaded && widget.config && !widget.opened) { widget.open(); stop() }
    }
    IpcHandler {
        target: "preview"
        function open() { widget.open() }
        function period(value: string) { widget.selectPeriod(value) }
        function state(): string { return JSON.stringify({loaded: widget.loaded, configured: !!widget.config, opened: widget.opened, period: widget.period, count: widget.series ? widget.series.points.length : 0, quote: widget.quoteStatus, history: widget.historyStatus, error: widget.configError}) }
    }
    Timer { interval: 120000; running: true; onTriggered: Qt.quit() }
}
