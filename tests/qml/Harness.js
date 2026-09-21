.pragma library

// Minimal assertion helper for QML/JS unit tests run by tests/run-qml-test.sh.
var failures = []
var passed = 0

function format(value) {
    try { return JSON.stringify(value) } catch (error) { return String(value) }
}

function ok(condition, message) {
    if (condition) passed += 1
    else failures.push(message)
}

function eq(actual, expected, message) {
    const same = format(actual) === format(expected)
    ok(same, message + ": expected " + format(expected) + ", got " + format(actual))
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

function finish(name) {
    for (const failure of failures) console.info("FAIL " + name + ": " + failure)
    if (failures.length) console.info("TESTS FAILED " + name + " (" + failures.length + " failed, " + passed + " passed)")
    else console.info("TESTS PASSED " + name + " (" + passed + " assertions)")
}
