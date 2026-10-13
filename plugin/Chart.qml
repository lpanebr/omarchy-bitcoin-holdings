import QtQuick
import qs.Commons
import "ChartModel.js" as Model

FocusScope {
    id: root
    property var points: []
    property real quantity: 0
    property string currency: "BRL"
    property int step: 86400
    property int selectedIndex: -1
    readonly property int leftPad: Style.space(120)
    readonly property int rightPad: Style.space(12)
    readonly property int topPad: Style.space(15)
    readonly property int bottomPad: Style.space(34)
    readonly property real plotWidth: Math.max(1, width - leftPad - rightPad)
    readonly property real plotHeight: Math.max(1, height - topPad - bottomPad)
    readonly property var values: points.map(function(p) { return p[1] * root.quantity })
    readonly property real minimum: values.length ? Math.min.apply(null, values) : 0
    readonly property real maximum: values.length ? Math.max.apply(null, values) : 1
    readonly property real margin: maximum === minimum ? Math.max(1, Math.abs(maximum) * 0.05) : (maximum - minimum) * 0.08
    readonly property real low: Math.max(0, minimum - margin)
    readonly property real high: maximum + margin
    readonly property real firstTime: points.length ? points[0][0] : 0
    readonly property real lastTime: points.length ? points[points.length - 1][0] : 1
    readonly property var selected: selectedIndex >= 0 && selectedIndex < points.length ? points[selectedIndex] : null
    readonly property color lineColor: points.length > 1 && points[points.length - 1][1] < points[0][1] ? Color.urgent : Color.accent
    readonly property var reduced: Model.reduce(points, plotWidth, step)
    implicitHeight: Style.space(250)
    activeFocusOnTab: points.length > 0
    Accessible.role: Accessible.Chart
    Accessible.name: "Valor da quantidade fixa em " + currency + ". Use setas para consultar pontos, Home e End para extremos."
    function xFor(t) { return leftPad + (lastTime === firstTime ? plotWidth / 2 : (t - firstTime) / (lastTime - firstTime) * plotWidth) }
    function yFor(v) { return topPad + (1 - (v - low) / (high - low)) * plotHeight }
    function repaint() { plot.requestPaint() }
    onPointsChanged: { selectedIndex = points.length - 1; repaint() }
    onQuantityChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()
    onLineColorChanged: repaint()
    onActiveFocusChanged: repaint()
    onSelectedIndexChanged: repaint()
    Keys.onLeftPressed: selectedIndex = Math.max(0, selectedIndex - 1)
    Keys.onRightPressed: selectedIndex = Math.min(points.length - 1, selectedIndex + 1)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) { selectedIndex = points.length ? 0 : -1; event.accepted = true }
        else if (event.key === Qt.Key_End) { selectedIndex = points.length - 1; event.accepted = true }
    }

    Canvas {
        id: plot
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
            ctx.lineWidth = 1
            for (var j = 0; j < 4; j++) {
                var y = root.topPad + j / 3 * root.plotHeight
                ctx.beginPath(); ctx.moveTo(root.leftPad, y); ctx.lineTo(width - root.rightPad, y); ctx.stroke()
            }
            if (!root.points.length) return
            var gaps = []
            for (var g = 1; g < root.points.length; g++)
                if (root.points[g][0] - root.points[g - 1][0] > root.step * 1.5) gaps.push([root.points[g - 1][0], root.points[g][0]])
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.beginPath()
            var gapIndex = 0
            for (var i = 0; i < root.reduced.length; i++) {
                var p = root.reduced[i], previous = i ? root.reduced[i - 1] : null
                while (gapIndex < gaps.length && previous && gaps[gapIndex][1] <= previous[0]) gapIndex++
                var broken = previous && gapIndex < gaps.length && gaps[gapIndex][0] >= previous[0] && gaps[gapIndex][1] <= p[0]
                var x = root.xFor(p[0]), py = root.yFor(p[1] * root.quantity)
                if (i === 0 || broken) ctx.moveTo(x, py)
                else ctx.lineTo(x, py)
            }
            ctx.stroke()
            if (root.selected) {
                var sx = root.xFor(root.selected[0]), sy = root.yFor(root.selected[1] * root.quantity)
                ctx.strokeStyle = Color.muted
                ctx.setLineDash([3, 4])
                ctx.beginPath(); ctx.moveTo(sx, root.topPad); ctx.lineTo(sx, height - root.bottomPad); ctx.stroke()
                ctx.setLineDash([])
                ctx.fillStyle = root.lineColor
                ctx.beginPath(); ctx.arc(sx, sy, 4, 0, 2 * Math.PI); ctx.fill()
            }
            if (root.activeFocus) {
                ctx.strokeStyle = Color.accent
                ctx.strokeRect(1, 1, width - 2, height - 2)
            }
        }
    }
    Repeater {
        model: 4
        Text {
            required property int index
            x: 0
            y: root.topPad + index / 3 * root.plotHeight - height / 2
            width: root.leftPad - Style.space(8)
            horizontalAlignment: Text.AlignRight
            text: Model.money(root.high - index / 3 * (root.high - root.low), root.currency)
            elide: Text.ElideRight
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
    Text {
        x: root.leftPad; y: root.height - root.bottomPad + Style.space(8)
        text: root.points.length ? Model.dateText(root.firstTime, false) : ""
        color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: root.rightPad
        y: root.height - root.bottomPad + Style.space(8)
        text: root.points.length > 1 ? Model.dateText(root.lastTime, false) : ""
        color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption
    }
    Text {
        anchors.centerIn: parent
        visible: root.points.length === 0
        text: "Sem pontos disponíveis"
        color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function(mouse) {
            var fraction = Math.max(0, Math.min(1, (mouse.x - root.leftPad) / root.plotWidth))
            root.selectedIndex = Model.nearest(root.points, root.firstTime + fraction * (root.lastTime - root.firstTime))
        }
        onClicked: root.forceActiveFocus()
    }
    Connections {
        target: Color
        function onForegroundChanged() { root.repaint() }
        function onMutedChanged() { root.repaint() }
    }
}
