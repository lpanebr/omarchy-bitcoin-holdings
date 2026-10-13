import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "ChartModel.js" as ChartModel

FocusScope {
    id: root
    required property var model
    property bool editing: false
    property string editCurrency: "BRL"
    readonly property var points: model.series ? model.series.points : []
    readonly property var change: ChartModel.variation(points, model.quantity)
    readonly property var periods: [{key: "week", label: "Semana"}, {key: "month", label: "Mês"}, {key: "year", label: "Ano"}, {key: "five", label: "5 anos"}]
    implicitWidth: Style.space(660)
    implicitHeight: Style.space(editing || !model.config ? 310 : 570)
    focus: true
    function prepareEdit() {
        editCurrency = model.currency
        amount.text = model.config ? model.config.amount.replace(".", ",") : ""
        Qt.callLater(function() { amount.forceActiveFocus() })
    }
    function stateText(status, error, hasData, old) {
        if (status === "loading") return old ? "Dados antigos · Atualizando…" : hasData ? "Atualizando…" : "Carregando…"
        if (status === "stale") return "Dados antigos" + (error ? " · " + error : "")
        if (status === "offline") return "Offline · " + error
        if (status === "unavailable") return "Indisponível" + (error ? " · " + error : "")
        return ""
    }
    Shortcut { sequence: "Escape"; enabled: model.opened; onActivated: model.close() }

    Controls.ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        ColumnLayout {
            width: root.width
            spacing: Style.space(12)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "₿ Bitcoin Holdings"
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body * 1.2
                    font.bold: true
                    Layout.fillWidth: true
                }
                Ui.Button {
                    text: root.editing ? "Voltar" : "Configurar"
                    visible: !!model.config
                    focusable: true
                    onClicked: { root.editing = !root.editing; if (root.editing) root.prepareEdit() }
                }
                Ui.Button {
                    text: "Atualizar"
                    visible: !!model.config && !root.editing
                    enabled: model.quoteStatus !== "loading" && model.historyStatus !== "loading"
                    focusable: true
                    onClicked: model.refresh(true)
                }
            }
            Text {
                visible: model.configError !== ""
                text: model.configError
                color: Color.urgent
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font.family: Style.font.family; font.pixelSize: Style.font.body
            }
            ColumnLayout {
                visible: root.editing || !model.config
                Layout.fillWidth: true
                spacing: Style.space(16)
                Text {
                    text: "Quanto BTC você quer acompanhar?"
                    color: Color.popups.text
                    font.family: Style.font.family; font.pixelSize: Style.font.body * 1.2
                }
                Text {
                    text: "Informe sua quantidade fixa. Ela fica salva apenas neste computador."
                    wrapMode: Text.Wrap
                    color: Color.muted
                    Layout.fillWidth: true
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                }
                Text { text: "Quantidade de BTC"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
                Ui.TextField {
                    id: amount
                    Layout.fillWidth: true
                    placeholderText: "Até 8 casas decimais"
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    maximumLength: 30
                    Accessible.name: "Quantidade de BTC"
                    onAccepted: if (!model.saving) model.save(text, root.editCurrency)
                }
                Ui.Dropdown {
                    label: "Moeda"
                    options: ["BRL", "USD", "EUR"]
                    value: root.editCurrency
                    Layout.fillWidth: true
                    onChanged: function(value) { root.editCurrency = value }
                }
                Ui.Button {
                    text: model.saving ? "Salvando…" : "Salvar"
                    focusable: true
                    bordered: true
                    enabled: model.ready && model.loaded && !model.saving
                    onClicked: model.save(amount.text, root.editCurrency)
                }
            }
            ColumnLayout {
                visible: !root.editing && !!model.config
                Layout.fillWidth: true
                spacing: Style.space(10)
                Text {
                    text: model.current ? ChartModel.money(model.current.price * model.quantity, model.currency) : "— " + model.currency
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body * 2.5
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: (model.config ? model.config.amount.replace(".", ",") : "") + " BTC · " + model.currency
                    color: Color.muted
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                }
                Text {
                    text: root.change.amount === null ? "" : (root.change.amount > 0 ? "+" : "") + ChartModel.money(root.change.amount, model.currency) + "  (" + (root.change.percent === null ? "percentual não aplicável" : Number(root.change.percent).toLocaleString(Qt.locale("pt_BR"), "f", 2) + "%") + ") no período"
                    color: root.change.amount < 0 ? Color.urgent : Color.accent
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                Text {
                    text: root.stateText(model.quoteStatus, model.quoteError, !!model.current)
                    visible: text !== ""
                    color: model.quoteStatus === "loading" ? Color.muted : Color.urgent
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                RowLayout {
                    spacing: Style.space(6)
                    Repeater {
                        model: root.periods
                        Ui.Button {
                            required property var modelData
                            text: modelData.label
                            selected: root.model.period === modelData.key
                            focusable: true
                            onClicked: root.model.selectPeriod(modelData.key)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: model.currency; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                }
                Chart {
                    id: chart
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    points: root.points
                    quantity: model.quantity
                    currency: model.currency
                    step: model.series ? model.series.step : 86400
                }
                Text {
                    text: chart.selected ? ChartModel.dateText(chart.selected[0], true) + " · " + ChartModel.money(chart.selected[1] * model.quantity, model.currency) : "Aponte para o gráfico ou use Tab e as setas."
                    color: Color.popups.text
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                Text {
                    text: root.stateText(model.historyStatus, model.historyError, !!model.series, model.historyOld)
                    visible: text !== ""
                    color: model.historyStatus === "loading" ? Color.muted : Color.urgent
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                Text {
                    text: root.points.length ? "Intervalo disponível: " + ChartModel.dateText(root.points[0][0], true) + " → " + ChartModel.dateText(root.points[root.points.length - 1][0], true) + (model.series && model.series.gaps ? " · " + model.series.gaps + " lacuna(s)" : "") : ""
                    color: Color.muted
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                Text {
                    text: model.current ? model.current.source + " · Última cotação: " + ChartModel.dateText(model.current.timestamp, true) : ""
                    color: Color.muted
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                Text {
                    text: "Valor hipotético da quantidade fixa em cada data.\nDatas no fuso local; intervalos calculados em UTC."
                    color: Color.muted
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
            }
        }
    }
}
