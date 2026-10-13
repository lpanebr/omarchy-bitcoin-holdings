import QtQuick
import Quickshell
import "plugin" as Holdings
import "plugin/ChartModel.js" as Model

ShellRoot {
    property int phase: 0
    property int ticks: 0
    PanelWindow {
        visible: false
        Holdings.BarWidget { id: widget }
    }
    Holdings.Chart {
        id: chart
        width: 600
        height: 250
        points: [[1, 10], [2, 20], [3, 5]]
        quantity: 0.5
    }
    Timer {
        running: true; repeat: true; interval: 100
        onTriggered: {
            if (++ticks > 80) { console.error("Tempo excedido no teste QML"); Qt.quit(); return }
            if (!widget.loaded) return
            if (phase === 0) {
                if (widget.config !== null) throw new Error("Primeira execução inventou quantidade")
                if (Model.money(1234.56, "BRL").indexOf("1.234,56") < 0) throw new Error("Formatação monetária inválida")
                if (Model.variation([[1, 10], [2, 20]], 0).percent !== null) throw new Error("Percentual de zero")
                if (Model.nearest([[1, 10], [4, 20]], 3) !== 1) throw new Error("Ponto mais próximo")
                var many = []
                for (var i = 0; i < 1800; i++) many.push([i, i === 999 ? 10000 : i === 777 ? 0 : 10])
                var reduced = Model.reduce(many, 300, 1)
                if (!reduced.some(function(p) { return p[1] === 10000 }) || !reduced.some(function(p) { return p[1] === 0 })) throw new Error("Redução perdeu extremos")
                widget.save("-1", "BRL")
                phase = 1
            } else if (phase === 1 && !widget.saving) {
                if (!widget.configError || widget.config !== null) throw new Error("Quantidade inválida foi aceita")
                widget.save("0,12345678", "BRL")
                phase = 2
            } else if (phase === 2 && widget.config) {
                if (widget.config.satoshis !== 12345678) throw new Error("Precisão foi perdida")
                var old = widget.quantity
                widget.save("0", "BRL")
                phase = 3
            } else if (phase === 3 && !widget.saving && widget.config.satoshis === 0) {
                var retained = {price: 100, timestamp: 1}
                widget.current = retained
                widget.latest = {quote: 100, history: 200}
                widget.inFlight = {command: "quote", id: 99}
                widget.receive(JSON.stringify({id: 99, ok: true, kind: "quote", currency: "BRL", status: "ready", data: {price: 999}}))
                if (widget.current.price !== 100) throw new Error("Resposta atrasada sobrescreveu a cotação")
                widget.inFlight = {command: "quote", id: 100}
                widget.receive(JSON.stringify({id: 100, ok: true, kind: "quote", currency: "EUR", status: "ready", data: {price: 999}}))
                if (widget.current.price !== 100) throw new Error("Resposta de outra moeda foi aplicada")
                widget.period = "five"
                widget.series = null
                widget.inFlight = {command: "history", id: 200}
                widget.receive(JSON.stringify({id: 200, ok: true, kind: "history", currency: "BRL", period: "month", status: "ready", data: {points: [[1, 999]]}}))
                if (widget.series !== null) throw new Error("Resposta de outro período foi aplicada")
                widget.ready = false
                widget.queue = []
                widget.historyCache = {
                    "BRL:month": {points: [[1, 10]], step: 3600, fetched_at: Date.now() / 1000},
                    "BRL:five": {points: [[2, 20]], step: 86400, fetched_at: 1}
                }
                widget.selectPeriod("month")
                if (!widget.series || widget.series.points[0][1] !== 10 || widget.historyStatus !== "loading")
                    throw new Error("Troca não mostrou cache imediatamente")
                if (!widget.queue[0].force) throw new Error("Troca não agendou atualização após cache")
                var olderId = widget.latest.history
                widget.selectPeriod("five")
                if (!widget.series || widget.series.points[0][1] !== 20 || !widget.historyOld)
                    throw new Error("Cache antigo não foi mostrado/identificado")
                widget.inFlight = {command: "history", id: olderId}
                widget.receive(JSON.stringify({id: olderId, ok: true, kind: "history", currency: "BRL", period: "month", status: "ready", data: {points: [[1, 999]]}}))
                if (widget.series.points[0][1] !== 20) throw new Error("Resposta atrasada substituiu cache selecionado")
                widget.inFlight = {command: "history", id: widget.latest.history}
                widget.receive(JSON.stringify({id: widget.latest.history, ok: true, kind: "history", currency: "BRL", period: "five", status: "stale", error: "Offline", data: null}))
                if (widget.series.points[0][1] !== 20 || widget.historyStatus !== "stale")
                    throw new Error("Falha apagou o gráfico em cache")
                widget.selectPeriod("year")
                if (widget.series !== null) throw new Error("Período sem cache mostrou série de outro período")
                chart.points = [[1, 1]]
                chart.quantity = 0
                console.log("HOLDINGS_SMOKE_PASS")
                Qt.quit()
            }
        }
    }
}
