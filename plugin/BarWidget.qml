import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "ChartModel.js" as ChartModel

Ui.BarWidget {
    id: root
    moduleName: "io.github.lpanebr.bitcoin-holdings"
    property bool opened: false
    property bool popoutSwitchClosing: false
    property var config: null
    property var current: null
    property var series: null
    property var historyCache: ({})
    property bool historyOld: false
    property string period: "month"
    property string quoteStatus: "loading"
    property string historyStatus: "idle"
    property string quoteError: ""
    property string historyError: ""
    property string configError: ""
    property bool loaded: false
    property bool saving: false
    property bool busy: false
    property bool ready: false
    property int sequence: 0
    property var latest: ({})
    property var queue: []
    property var inFlight: null
    readonly property real quantity: config ? config.satoshis / 100000000 : 0
    readonly property string currency: config ? config.currency : "BRL"
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("holdings.py")).replace(/^file:\/\//, ""))
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() { opened = true }
    function close() { opened = false }
    function toggle() { opened = !opened }
    function closeForPopoutSwitch() {
        popoutSwitchClosing = true
        opened = false
        Qt.callLater(function() { root.popoutSwitchClosing = false })
    }
    function enqueue(command, extras) {
        var message = {command: command, id: ++sequence}
        for (var key in extras) message[key] = extras[key]
        var ids = Object.assign({}, latest)
        ids[command] = message.id
        latest = ids
        queue = queue.filter(function(item) { return item.command !== command }).concat([message])
        dispatch()
    }
    function dispatch() {
        if (!ready || busy || queue.length === 0) return
        var next = queue[0]
        queue = queue.slice(1)
        inFlight = next
        busy = true
        helper.write(JSON.stringify(next) + "\n")
    }
    function receive(line) {
        var response
        try { response = JSON.parse(line) }
        catch (error) { configError = "Resposta inválida do helper local."; return }
        var request = inFlight
        busy = false
        inFlight = null
        if (request && response.id === latest[request.command]) {
            if (!response.ok) {
                if (request.command === "load" || request.command === "save") {
                    configError = response.error
                    loaded = true
                    saving = false
                } else if (request.command === "quote") { quoteStatus = current ? "stale" : "unavailable"; quoteError = response.error }
                else { historyStatus = series ? "stale" : "unavailable"; historyError = response.error }
            } else if (response.kind === "config") {
                var changedCurrency = !config || !response.config || config.currency !== response.config.currency
                config = response.config
                configError = ""
                loaded = true
                saving = false
                if (changedCurrency) { current = null; series = null; historyStatus = "idle"; historyOld = false; quoteError = ""; historyError = "" }
                if (config && response.histories) {
                    var snapshots = Object.assign({}, historyCache)
                    for (var cachedPeriod in response.histories)
                        snapshots[currency + ":" + cachedPeriod] = response.histories[cachedPeriod]
                    historyCache = snapshots
                }
                if (response.quote && response.quote.data) {
                    current = response.quote.data
                    quoteStatus = response.quote.status
                }
                if (request.command === "save") {
                    panel.editing = false
                    panel.forceActiveFocus()
                    // Quantidade alterada reutiliza os preços já carregados.
                    broadcast("reloadConfig")
                }
                if (config && changedCurrency) refresh(false)
            } else if (response.currency === currency) {
                if (response.kind === "quote") {
                    if (response.data) current = response.data
                    quoteStatus = response.status
                    quoteError = response.error
                } else if (response.period === period) {
                    if (response.data) {
                        series = response.data
                        var snapshots = Object.assign({}, historyCache)
                        snapshots[currency + ":" + period] = response.data
                        historyCache = snapshots
                    }
                    historyStatus = response.status
                    historyOld = response.status === "stale"
                    historyError = response.error
                }
            }
        }
        Qt.callLater(dispatch)
    }
    function reloadConfig() { enqueue("load", {}) }
    function refresh(force) {
        if (!config || !loaded) return
        quoteStatus = "loading"
        enqueue("quote", {currency: currency, force: !!force})
        if (opened) fetchHistory(force)
    }
    function fetchHistory(force) {
        if (!config) return
        var cached = historyCache[currency + ":" + period]
        if (cached) series = cached
        var ttl = period === "week" || period === "month" ? 300 : 3600
        historyOld = !!series && (historyStatus === "stale" || Date.now() / 1000 - series.fetched_at >= ttl)
        historyStatus = "loading"
        enqueue("history", {currency: currency, period: period, force: !!force})
    }
    function selectPeriod(value) {
        if (value === period) return
        period = value
        series = null
        historyStatus = "idle"
        historyError = ""
        fetchHistory(true)
    }
    function save(amount, selectedCurrency) {
        saving = true
        configError = ""
        enqueue("save", {amount: amount, currency: selectedCurrency})
    }
    onOpenedChanged: if (opened) {
        panel.editing = !config
        if (panel.editing) panel.prepareEdit()
        if (config) fetchHistory(false)
    }

    Process {
        id: helper
        command: ["python3", "-u", root.helperPath]
        stdinEnabled: true
        running: true
        onStarted: { root.ready = true; root.reloadConfig() }
        stdout: SplitParser { onRead: function(line) { root.receive(line) } }
        onExited: {
            root.ready = false
            root.busy = false
            root.saving = false
            root.quoteStatus = root.current ? "stale" : "unavailable"
            root.historyStatus = root.series ? "stale" : "unavailable"
            root.configError = "Helper local encerrado. Recarregue o plugin."
        }
    }
    Timer { interval: 300000; repeat: true; running: root.loaded && !!root.config; onTriggered: root.refresh(false) }

    Ui.WidgetButton {
        id: button
        bar: root.bar
        text: root.vertical ? "₿" : !root.loaded ? "₿ …" : !root.config ? "Configurar BTC" : root.current ? "₿ " + ChartModel.money(root.current.price * root.quantity, root.currency) + (root.quoteStatus === "stale" ? " *" : "") : "₿ " + (root.quoteStatus === "loading" ? "…" : "Indisponível")
        active: root.opened
        tooltipText: !root.config ? "Informe a quantidade de BTC e a moeda" : "Bitcoin Holdings · " + root.currency + (root.quoteStatus === "stale" ? " · Dados antigos" : "") + (root.current ? "\n" + root.current.source + " · " + ChartModel.dateText(root.current.timestamp, true) : "")
        onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.toggle() }
    }
    Ui.KeyboardPanel {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        focusTarget: panel
        contentWidth: fittedContentWidth(panel.implicitWidth + padding * 2)
        contentHeight: fittedContentHeight(panel.implicitHeight + padding * 2)
        Panel {
            id: panel
            anchors.fill: parent
            model: root
        }
    }
}
