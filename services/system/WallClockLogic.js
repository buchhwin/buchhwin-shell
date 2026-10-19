.pragma library

// When the wall clock jumped (services/WallClock.qml). Qt's timers run on the
// monotonic clock, which stands still while the machine sleeps; the wall
// clock does not. Two ticks of a timer `intervalMs` apart are that far apart
// on the monotonic clock, so a wall clock that moved much more (a suspend in
// between) or much less (the time set back) has jumped. Half a step of slack,
// and at least 5 s, so a busy moment or an NTP nudge is no jump.
function jumped(previousMs, nowMs, intervalMs) {
    const slack = Math.max(5000, intervalMs / 2)
    return Math.abs((nowMs - previousMs) - intervalMs) > slack
}
