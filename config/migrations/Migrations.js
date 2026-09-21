.pragma library
.import "v1_to_v2.js" as V1

// Layout configuration migrations. migrate() never throws; callers must not
// write when `readOnly` is set (unknown future version or unreadable file).
var CURRENT_VERSION = 2

function emptyConfig() {
    return { configVersion: CURRENT_VERSION, activeProfile: "minimal", profiles: {} }
}

function migrate(input) {
    let parsed = input
    if (typeof input === "string") {
        if (!input.trim().length)
            return { ok: true, readOnly: false, changed: false, from: 0, to: CURRENT_VERSION, config: emptyConfig() }
        try {
            parsed = JSON.parse(input)
        } catch (error) {
            return { ok: false, readOnly: true, changed: false, from: -1, to: CURRENT_VERSION,
                     config: emptyConfig(), error: "invalid JSON: " + error }
        }
    }
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
        return { ok: false, readOnly: true, changed: false, from: -1, to: CURRENT_VERSION,
                 config: emptyConfig(), error: "layout is not an object" }

    const from = typeof parsed.configVersion === "number" ? parsed.configVersion : 1
    if (from > CURRENT_VERSION)
        return { ok: false, readOnly: true, changed: false, from: from, to: CURRENT_VERSION,
                 config: emptyConfig(), error: "layout version " + from + " is newer than this shell" }

    let config = parsed
    if (from < 2) config = V1.migrate(parsed)
    return { ok: true, readOnly: false, changed: from !== CURRENT_VERSION, from: from,
             to: CURRENT_VERSION, config: config }
}
