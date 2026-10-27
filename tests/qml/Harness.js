.pragma library

// Minimal assertion helper for QML/JS unit tests run by tests/run-qml-test.sh.
var failures = []
var passed = 0

// JSON writes NaN and Infinity as null and drops undefined and functions (or
// writes them as null in a list), so T.eq(NaN, null), T.eq(f, undefined) and
// T.eq({ a: undefined }, {}) all passed. Those are marked first and written
// out by name. -0 stays 0: tests compare it with 0 on purpose. The mark is
// a NUL, which JSON escapes: only a string that holds one could look like a
// mark (a private-use character would be a glyph's - Nerd Fonts live there).
const MARK = "\u0000"
function marked(key, value) {
    if (value === undefined) return MARK + "undefined"
    if (typeof value === "function") return MARK + "function"
    if (typeof value === "number" && !isFinite(value)) return MARK + String(value)
    return value
}

function format(value) {
    try {
        return JSON.stringify(value, marked).replace(/"\\u0000([^"]*)"/g, "$1")
    } catch (error) {
        return String(value)
    }
}

// Whether two values are the same to eq, without counting an assertion.
function same(actual, expected) {
    return format(actual) === format(expected)
}

function ok(condition, message) {
    if (condition) passed += 1
    else failures.push(message)
}

function eq(actual, expected, message) {
    ok(same(actual, expected), message + ": expected " + format(expected) + ", got " + format(actual))
}

function near(actual, expected, message, epsilon) {
    const limit = epsilon === undefined ? 1e-9 : epsilon
    ok(typeof actual === "number" && Math.abs(actual - expected) <= limit,
       message + ": expected ~" + expected + ", got " + format(actual))
}

function throwsError(callback, message) {
    try {
        callback()
        failures.push(message + ": expected an error")
    } catch (error) {
        passed += 1
    }
}

// Asks `pred` every 20 ms until it holds or `timeoutMs` (3000) passed, then
// calls done(held). For a step that needs something to have loaded: a fixed
// delay was too short while the machine was busy (a build beside the run).
// `parent` owns the Timer it polls with.
function waitUntil(parent, pred, timeoutMs, done) {
    const timer = Qt.createQmlObject("import QtQuick; Timer { interval: 20; repeat: true }", parent)
    let left = Math.ceil((timeoutMs || 3000) / 20)
    const held = () => { try { return !!pred() } catch (error) { return false } }
    timer.triggered.connect(() => {
        const now = held()
        if (!now && --left > 0) return
        timer.stop()
        timer.destroy()
        done(now)
    })
    timer.start()
}

function finish(name) {
    for (const failure of failures) console.info("FAIL " + name + ": " + failure)
    if (failures.length) console.info("TESTS FAILED " + name + " (" + failures.length + " failed, " + passed + " passed)")
    else console.info("TESTS PASSED " + name + " (" + passed + " assertions)")
}
