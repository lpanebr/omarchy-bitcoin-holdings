function money(value, currency) {
    if (value === null || value === undefined || !isFinite(value)) return "—"
    return Number(value).toLocaleCurrencyString(Qt.locale("pt_BR"), currency === "BRL" ? "R$" : currency === "USD" ? "US$" : "€")
}

function dateText(timestamp, time) {
    return Qt.formatDateTime(new Date(timestamp * 1000), time ? "dd/MM/yyyy HH:mm" : "dd/MM/yyyy")
}

function variation(points, quantity) {
    if (!points || !points.length) return {amount: null, percent: null}
    var first = points[0][1] * quantity
    var last = points[points.length - 1][1] * quantity
    return {amount: last - first, percent: first === 0 ? null : (last / first - 1) * 100}
}

// Retém mínimo/máximo de cada faixa de pixels, endpoints e ambos os lados
// de toda lacuna. Tooltip/teclado continuam usando a série completa.
function reduce(points, width, step) {
    if (!points || points.length < 3) return points || []
    var buckets = Math.max(1, Math.floor(width / 3))
    var first = points[0][0], span = points[points.length - 1][0] - first
    if (points.length <= buckets * 2 || span <= 0) return points
    var keep = {}, bins = {}
    keep[0] = true; keep[points.length - 1] = true
    for (var i = 0; i < points.length; i++) {
        var bucket = Math.min(buckets - 1, Math.floor((points[i][0] - first) / span * buckets))
        var bin = bins[bucket]
        if (!bin) bins[bucket] = {min: i, max: i}
        else {
            if (points[i][1] < points[bin.min][1]) bin.min = i
            if (points[i][1] > points[bin.max][1]) bin.max = i
        }
        if (i > 0 && points[i][0] - points[i - 1][0] > step * 1.5) {
            keep[i - 1] = true; keep[i] = true
        }
    }
    for (var key in bins) { keep[bins[key].min] = true; keep[bins[key].max] = true }
    return Object.keys(keep).map(Number).sort(function(a, b) { return a - b }).map(function(i) { return points[i] })
}

function nearest(points, moment) {
    if (!points || !points.length) return -1
    var low = 0, high = points.length - 1
    while (low < high) {
        var mid = Math.floor((low + high) / 2)
        if (points[mid][0] < moment) low = mid + 1
        else high = mid
    }
    return low > 0 && Math.abs(points[low - 1][0] - moment) < Math.abs(points[low][0] - moment) ? low - 1 : low
}
