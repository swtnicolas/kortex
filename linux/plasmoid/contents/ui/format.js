.pragma library

const GIB = 1024 * 1024 * 1024;
const MIB = 1024 * 1024;

function known(value) {
    return value !== null && value !== undefined && isFinite(value);
}

function decimal(value, decimals) {
    const rounded = Number(value.toFixed(decimals));
    return (Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(decimals)).replace(".", ",");
}

function bytes(value) {
    if (!known(value)) return "—";
    if (value >= GIB) return decimal(value / GIB, 2) + " GB";
    return decimal(value / MIB, 2) + " MB";
}

function percent(value) {
    return known(value) ? Math.round(value) + "%" : "—";
}

function listPercent(value) {
    if (!known(value)) return "—";
    if (value > 0 && value < 1) return decimal(value, 2) + "%";
    return Math.round(value) + "%";
}

function preciseCelsius(value) {
    return known(value) ? value.toFixed(1).replace(".", ",") + " °C" : "—";
}

function celsius(value) {
    return known(value) ? Math.round(value) + " °C" : "—";
}

function barValue(value, unit) {
    return known(value) ? Math.round(value) + unit : "—";
}

function number(value, unit) {
    return known(value) ? Math.round(value) + (unit ? " " + unit : "") : "—";
}

function gigahertz(megahertz, unit) {
    return known(megahertz) ? (megahertz / 1000).toFixed(2).replace(".", ",") + (unit ? " GHz" : "") : "—";
}

function watts(value) {
    return known(value) ? decimal(value, 1) + " W" : "—";
}

function pair(left, right, separator) {
    return left + (separator || " · ") + right;
}

function ago(seconds) {
    return seconds < 1 ? "ahora" : "hace " + seconds + " s";
}

function cost(percent) {
    return "Usa ~" + decimal(percent, percent < 0.1 ? 2 : 1) + "% de CPU";
}
