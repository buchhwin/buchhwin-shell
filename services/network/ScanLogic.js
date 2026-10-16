.pragma library

// Who keeps the Wi-Fi scan running. Every network view - the popup, the
// control-center page, the settings page - says when it arrives (true) and
// when it leaves (false), in pairs. Counted rather than switched, because the
// last view out used to win: the popup's "Network settings" link or the
// control center's gear opened Settings, whose page started the scan, and the
// popup's body, torn down about 260 ms later, stopped it again under the page
// (as BluetoothLogic.discoveryStep for the Bluetooth search).
function scanViewers(viewers, value) {
    const count = Math.max(0, Math.round(Number(viewers)) || 0)
    return value ? count + 1 : Math.max(0, count - 1)
}
