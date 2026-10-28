.pragma library

// Update check for Settings > Updates: parses the report of
// scripts/updates-check.sh (dnf5 JSON, rpm versions, advisories, flatpak
// remote-ls/list columns), builds labels and decides when the automatic check
// and the forced metadata refresh are due. Unit tested with synthetic output.

var HOUR = 3600000
var MINUTE = 60000
// A failed automatic check (offline) is retried after this long.
var RETRY_MS = HOUR
var CHECK_HOURS = [0, 6, 12, 24]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var SEVERITY_RANK = { "critical": 4, "important": 3, "moderate": 2, "low": 1 }

function emptyResult() {
    return { packages: [], flatpaks: [], packagesKnown: false, flatpaksKnown: false,
             packagesCached: false, flatpaksCached: false, packageError: "", flatpakError: "",
             offline: false, checked: false }
}

// "@NAME EXIT" headers → { NAME: { code, text } }; text before the first
// header is ignored.
function parseSections(text) {
    const sections = {}
    let current = null
    for (const line of String(text || "").split("\n")) {
        const match = /^@([a-z][a-z-]*) (-?\d+)$/.exec(line)
        if (match) {
            current = { code: parseInt(match[2]), lines: [] }
            sections[match[1]] = current
        } else if (current) {
            current.lines.push(line)
        }
    }
    const result = {}
    for (const name in sections) result[name] = { code: sections[name].code, text: sections[name].lines.join("\n").trim() }
    return result
}

// dnf check-upgrade --json exits 0 (JSON) or 100 (text mode) when upgrades exist.
function succeeded(section) {
    return !!section && (section.code === 0 || section.code === 100)
}

// Drops a zero or missing epoch ("0:1.2-3", "(none):1.2-3" → "1.2-3").
function cleanEvr(evr) {
    return String(evr || "").replace(/^(\(none\)|0):/, "")
}

function safeName(value) {
    return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._+~^:-]*$/.test(value) && value.length <= 200
}

// dnf5 check-upgrade --json → [{ name, arch, version, repository }], null for broken output.
function parseDnf(text) {
    let data = null
    try { data = JSON.parse(String(text || "").trim() || "{}") } catch (error) { return null }
    if (!data || typeof data !== "object" || Array.isArray(data)) return null
    const list = Array.isArray(data.upgrades) ? data.upgrades : []
    const seen = {}
    const result = []
    for (const item of list) {
        if (!item || !safeName(item.name) || !safeName(item.arch)) continue
        const key = item.name + "." + item.arch
        if (seen[key]) continue
        seen[key] = true
        result.push({ name: item.name, arch: item.arch, version: cleanEvr(item.evr),
                      repository: typeof item.repository === "string" ? item.repository : "" })
    }
    return result
}

// "name-version-release.arch" (the version never contains "-").
function splitNevra(nevra) {
    const match = /^(.+)-([^-]+)-([^-]+)\.([^.-]+)$/.exec(String(nevra || ""))
    return match ? { name: match[1], arch: match[4], version: cleanEvr(match[2] + "-" + match[3]) } : null
}

// dnf5 advisory list --json → { "name.arch": { type, severity, id } } for
// security advisories (the most severe one per package).
function parseAdvisories(text) {
    let data = null
    try { data = JSON.parse(String(text || "").trim() || "[]") } catch (error) { return {} }
    const result = {}
    if (!Array.isArray(data)) return result
    for (const item of data) {
        if (!item || String(item.type).toLowerCase() !== "security") continue
        const package_ = splitNevra(item.nevra)
        if (!package_) continue
        const key = package_.name + "." + package_.arch
        const severity = String(item.severity || "").toLowerCase()
        const previous = result[key]
        if (previous && (SEVERITY_RANK[previous.severity] || 0) >= (SEVERITY_RANK[severity] || 0)) continue
        result[key] = { type: "security", severity: SEVERITY_RANK[severity] ? severity : "", id: String(item.name || "") }
    }
    return result
}

// rpm "NAME.ARCH<TAB>EPOCH:VERSION-RELEASE" lines → { "name.arch": version }.
function parseInstalled(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        const parts = line.split("\t")
        if (parts.length !== 2 || !parts[0].length || !parts[1].length) continue
        result[parts[0]] = cleanEvr(parts[1])
    }
    return result
}

// Arch's @local-builds: one package name a line → { name: true }.
function parseNames(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        const name = line.trim()
        if (safeName(name)) result[name] = true
    }
    return result
}

// flatpak remote-ls --updates --columns=application,name,version,branch,origin,ref
function parseFlatpakUpdates(text, installation) {
    const result = []
    for (const line of String(text || "").split("\n")) {
        const parts = line.split("\t")
        if (parts.length < 6 || !safeName(parts[0])) continue
        const kind = parts[5].startsWith("runtime/") ? "runtime" : "app"
        result.push({ id: parts[0], name: parts[1] || parts[0], version: parts[2], branch: parts[3],
                      origin: parts[4], kind: kind, installation: installation })
    }
    return result
}

function flatpakKey(installation, id, branch) {
    return installation + "/" + id + "/" + branch
}

// flatpak list --columns=application,branch,version,installation
function parseFlatpakInstalled(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        const parts = line.split("\t")
        if (parts.length < 4 || !parts[0].length) continue
        result[flatpakKey(parts[3], parts[0], parts[1])] = parts[2]
    }
    return result
}

function lastLine(text) {
    const lines = String(text || "").split("\n").map(line => line.trim())
        .filter(line => line.length && !/^(Updating and loading repositories|Repositories loaded)/.test(line)
                && !/^[>\s]*\d+%|\[[=\s-]*\]/.test(line))
    const line = lines.length ? lines[lines.length - 1].replace(/^error:\s*/i, "") : ""
    return line.length > 160 ? line.slice(0, 157) + "…" : line
}

// checkupdates (Arch) says only "Cannot fetch updates" when its private
// `pacman -Sy` cannot reach a mirror.
function isOffline(stderr) {
    return /Cannot fetch updates|Curl error|Could not resolve|Couldn't resolve|Could not connect|Network is unreachable|Temporary failure in name resolution|No route to host|Failed to download metadata|Unable to load summary|Timeout was reached/i.test(String(stderr || ""))
}

// Readable text for a failed section. tool: "dnf" or "flatpak".
function errorText(tool, section, stderr) {
    const label = tool === "dnf" ? "System packages" : "Flatpaks"
    if (!section) return label + ": no result"
    // The check names what is missing where it knows better (Arch:
    // checkupdates and its package); dnf5 and flatpak are the defaults.
    if (section.code === 127) return lastLine(stderr) || (tool === "dnf" ? "dnf5 is not installed" : "Flatpak is not installed")
    if (section.code === 124) return label + ": the check timed out"
    if (isOffline(stderr)) return "Offline: the update servers could not be reached"
    const detail = lastLine(stderr)
    return label + ": check failed" + (detail.length ? " (" + detail + ")" : " (exit " + section.code + ")")
}

function versionSort(a, b) {
    return a.name.localeCompare(b.name) || a.arch.localeCompare(b.arch)
}

// The full report → result object used by the service and the page.
function parseReport(text) {
    const sections = parseSections(text)
    const result = emptyResult()
    const stderr = name => sections[name + "-stderr"] ? sections[name + "-stderr"].text : ""

    // System packages.
    const dnf = sections["dnf"]
    const cached = sections["dnf-cached"]
    let packages = succeeded(dnf) ? parseDnf(dnf.text) : null
    if (dnf && (!succeeded(dnf) || packages === null)) {
        result.packageError = packages === null && succeeded(dnf) ? "System packages: unreadable dnf output" : errorText("dnf", dnf, stderr("dnf"))
        result.offline = result.offline || isOffline(stderr("dnf"))
        if (succeeded(cached)) {
            packages = parseDnf(cached.text)
            result.packagesCached = packages !== null
        }
    }
    if (packages !== null) {
        const installed = sections["installed"] ? parseInstalled(sections["installed"].text) : {}
        const advisories = sections["advisories"] && sections["advisories"].code === 0 ? parseAdvisories(sections["advisories"].text) : {}
        const builtHere = sections["local-builds"] && sections["local-builds"].code === 0 ? parseNames(sections["local-builds"].text) : {}
        result.packages = packages.map(item => {
            const key = item.name + "." + item.arch
            const advisory = advisories[key]
            return { name: item.name, arch: item.arch, from: installed[key] || "", to: item.version,
                     repository: item.repository, security: !!advisory,
                     severity: advisory ? advisory.severity : "", advisory: advisory ? advisory.id : "",
                     localBuild: builtHere[item.name] === true }
        }).sort((a, b) => (b.security - a.security) || (SEVERITY_RANK[b.severity] || 0) - (SEVERITY_RANK[a.severity] || 0) || versionSort(a, b))
        result.packagesKnown = true
    }

    // Flatpaks of both installations.
    const installedFlatpaks = sections["flatpak-installed"] ? parseFlatpakInstalled(sections["flatpak-installed"].text) : {}
    const flatpaks = []
    let flatpakKnown = false
    const flatpakErrors = []
    for (const installation of ["system", "user"]) {
        const name = "flatpak-" + installation
        const live = sections[name]
        if (!live) continue
        let source = live
        if (live.code !== 0) {
            const error = errorText("flatpak", live, stderr(name))
            if (flatpakErrors.indexOf(error) < 0) flatpakErrors.push(error)
            result.offline = result.offline || isOffline(stderr(name))
            source = sections[name + "-cached"] && sections[name + "-cached"].code === 0 ? sections[name + "-cached"] : null
            if (source) result.flatpaksCached = true
        }
        if (!source) continue
        flatpakKnown = true
        for (const item of parseFlatpakUpdates(source.text, installation)) {
            item.from = installedFlatpaks[flatpakKey(installation, item.id, item.branch)] || ""
            item.to = item.version
            flatpaks.push(item)
        }
    }
    result.flatpaks = flatpaks.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === "app" ? -1 : 1)
        || a.name.localeCompare(b.name) || a.installation.localeCompare(b.installation))
    result.flatpaksKnown = flatpakKnown
    result.flatpakError = flatpakErrors.join(" · ")
    // A check counts when at least one source answered from the network.
    result.checked = (!!dnf && succeeded(dnf) && result.packagesKnown && !result.packagesCached)
        || ["system", "user"].some(installation => sections["flatpak-" + installation] && sections["flatpak-" + installation].code === 0)
    return result
}

// ---- labels -----------------------------------------------------------------

function plural(count, singular, pluralText) {
    return count + " " + (count === 1 ? singular : pluralText)
}

function securityCount(result) {
    return result.packages.filter(item => item.security).length
}

function total(result) {
    return result.packages.length + result.flatpaks.length
}

function userFlatpaks(result) {
    return result.flatpaks.filter(item => item.installation === "user")
}

// "System installation", "User installation" or "2 system · 1 user".
function installationsText(result) {
    const user = userFlatpaks(result).length
    const system = result.flatpaks.length - user
    if (!result.flatpaks.length) return ""
    if (!user) return "System installation"
    if (!system) return "User installation"
    return system + " system · " + user + " user"
}

function versionText(from, to) {
    if (!to) return from
    if (!from) return to
    if (from === to) return to + " · new build"
    return from + " → " + to
}

function packageSubtitle(item) {
    const parts = [versionText(item.from, item.to)]
    if (item.repository) parts.push(item.repository)
    if (item.localBuild) parts.push("replaces your own build")
    return parts.join(" · ")
}

function flatpakSubtitle(item) {
    const parts = [versionText(item.from, item.to) || item.branch]
    parts.push(item.kind === "runtime" ? "Runtime" : "App")
    parts.push(item.installation === "user" ? "User" : "System")
    return parts.filter(part => part.length).join(" · ")
}

function severityLabel(severity) {
    return severity.length ? severity.charAt(0).toUpperCase() + severity.slice(1) : "Security"
}

// "12 updates available" / "Up to date".
function summary(result) {
    const count = total(result)
    if (!result.packagesKnown && !result.flatpaksKnown) return "Not checked yet"
    return count ? plural(count, "update", "updates") + " available" : "Up to date"
}

function notifyTitle(result) {
    return plural(total(result), "update", "updates") + " available"
}

function notifyBody(result) {
    const parts = []
    if (result.packages.length) parts.push(plural(result.packages.length, "system package", "system packages"))
    if (result.flatpaks.length) parts.push(plural(result.flatpaks.length, "Flatpak", "Flatpaks"))
    const security = securityCount(result)
    if (security) parts.push(plural(security, "security update", "security updates"))
    const local = localBuilds(result)
    if (local.length) parts.push("replaces your own build of " + listText(local.map(item => item.name)))
    return parts.join(" · ")
}

function pad(value) {
    return (value < 10 ? "0" : "") + value
}

// "Just now", "5 minutes ago", "Today, 14:05", "Yesterday, 09:30", "Sep 12, 18:00".
function checkedText(time, now) {
    if (!time) return "Never"
    const diff = now - time
    if (diff >= 0 && diff < MINUTE) return "Just now"
    if (diff >= 0 && diff < HOUR) return plural(Math.floor(diff / MINUTE), "minute", "minutes") + " ago"
    const date = new Date(time)
    const today = new Date(now)
    const clock = pad(date.getHours()) + ":" + pad(date.getMinutes())
    // Calendar days, not 24-hour windows: on the night the clocks change a
    // day is 23 or 25 hours long, and "yesterday" measured as `dayStart -
    // 24h` then started an hour into it or an hour before it.
    const dayOf = value => new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime()
    const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
    if (dayOf(date) === dayOf(today)) return "Today, " + clock
    if (dayOf(date) === dayOf(yesterday)) return "Yesterday, " + clock
    return MONTHS[date.getMonth()] + " " + date.getDate() + (date.getFullYear() !== today.getFullYear() ? " " + date.getFullYear() : "") + ", " + clock
}

// ---- schedule and notifications ---------------------------------------------

function validHours(hours) {
    return CHECK_HOURS.indexOf(hours) >= 0 ? hours : 24
}

// Automatic check: interval passed since the last successful check and no
// failed attempt within the retry delay.
function checkDue(now, state, hours) {
    if (!hours || CHECK_HOURS.indexOf(hours) < 0) return false
    if (now - (state.lastCheck || 0) < hours * HOUR) return false
    return now - (state.lastAttempt || 0) >= Math.min(RETRY_MS, hours * HOUR)
}

// dnf --refresh at most once per interval (24 h while automatic checks are off).
function refreshDue(now, state, hours) {
    const interval = (hours > 0 ? hours : 24) * HOUR
    return now - (state.lastRefresh || 0) >= interval
}

function itemKeys(result) {
    return result.packages.map(item => "rpm:" + item.name + "." + item.arch + "@" + item.to)
        .concat(result.flatpaks.map(item => "flatpak:" + flatpakKey(item.installation, item.id, item.branch) + "@" + item.to))
        .sort()
}

// Updates not part of the last notified set.
function newKeys(keys, notified) {
    const known = {}
    for (const key of notified || []) known[key] = true
    return keys.filter(key => !known[key])
}

function parseState(text) {
    let data = null
    try { data = JSON.parse(String(text || "")) } catch (error) { data = null }
    const number = value => typeof value === "number" && isFinite(value) && value > 0 ? value : 0
    const state = { lastCheck: 0, lastAttempt: 0, lastRefresh: 0, notified: [], result: null, shell: null }
    if (!data || typeof data !== "object" || data.version !== 1) return state
    state.lastCheck = number(data.lastCheck)
    state.lastAttempt = number(data.lastAttempt)
    state.lastRefresh = number(data.lastRefresh)
    state.notified = Array.isArray(data.notified) ? data.notified.filter(key => typeof key === "string").slice(0, 2000) : []
    if (data.result && Array.isArray(data.result.packages) && Array.isArray(data.result.flatpaks))
        state.result = Object.assign(emptyResult(), data.result)
    if (data.shell && typeof data.shell === "object" && Array.isArray(data.shell.commits))
        state.shell = Object.assign(emptyShell(), data.shell)
    // Arch's news and .pacnew files, from a file that has them (UpdatesService
    // reads a missing one as none).
    if (data.extras && typeof data.extras === "object") state.extras = cleanExtras(data.extras)
    return state
}

function serializeState(state) {
    return JSON.stringify({ version: 1, lastCheck: state.lastCheck, lastAttempt: state.lastAttempt,
                            lastRefresh: state.lastRefresh, notified: state.notified, result: state.result,
                            shell: state.shell, extras: state.extras || emptyExtras() }, null, 2) + "\n"
}

// ---- the shell itself -----------------------------------------------------------
// scripts/shell-update.sh check: the checkout the session runs from against
// the remote it follows. `repo` is "ok" (follows a remote), "local" (follows
// none - the development machine's stable worktree) or "none" (not a git
// checkout at all).

function emptyShell() {
    return { known: false, repo: "", dir: "", branch: "", upstream: "", head: "",
             behind: 0, ahead: 0, dirty: false, commits: [], fetched: false, error: "" }
}

function parseShellReport(text) {
    const sections = parseSections(text)
    const shell = emptyShell()
    const repo = sections["repo"]
    if (!repo) { shell.error = "The shell check produced no report"; return shell }
    const lines = repo.text.split("\n")
    shell.known = true
    shell.repo = ["ok", "local", "none"].indexOf(lines[0]) >= 0 ? lines[0] : "none"
    shell.dir = lines[1] || ""
    shell.branch = lines[2] || ""
    shell.upstream = lines[3] || ""
    shell.head = lines[4] || ""
    if (shell.repo !== "ok") return shell
    const fetch = sections["fetch"]
    if (fetch && fetch.code !== 0) {
        const reason = fetch.text.split("\n")[0]
        shell.error = /Could not resolve|Could not connect|Connection timed out|Network is unreachable/i.test(fetch.text)
            ? "Offline: the shell's remote could not be reached"
            : "The shell's remote could not be fetched" + (reason.length ? " (" + reason + ")" : "")
    }
    shell.fetched = !!fetch && fetch.code === 0 && fetch.text !== "skipped"
    const count = name => sections[name] ? Math.max(0, parseInt(sections[name].text) || 0) : 0
    shell.behind = count("behind")
    shell.ahead = count("ahead")
    shell.dirty = !!sections["dirty"] && sections["dirty"].text.length > 0
    shell.commits = (sections["log"] ? sections["log"].text.split("\n") : []).filter(line => line.length).map(line => {
        const tab = line.indexOf("\t")
        return tab < 0 ? { hash: "", subject: line } : { hash: line.slice(0, tab), subject: line.slice(tab + 1) }
    })
    return shell
}

function shellSummary(shell) {
    if (!shell || !shell.known) return "Not checked yet"
    if (shell.repo === "none") return "Not a git checkout"
    if (shell.repo === "local") return "Development checkout, follows no remote"
    if (shell.behind > 0) return shell.behind + (shell.behind === 1 ? " commit" : " commits") + " behind " + shell.upstream
    return "Up to date"
}

function shellSubtitle(shell) {
    if (!shell || !shell.known || shell.repo === "none") return shell && shell.dir ? shell.dir : ""
    const parts = [shell.branch + " at " + shell.head]
    if (shell.ahead > 0) parts.push(shell.ahead + " local " + (shell.ahead === 1 ? "commit" : "commits"))
    if (shell.dirty) parts.push("local changes")
    if (shell.error.length) parts.push(shell.error)
    return parts.join(" · ")
}

// Fast-forward only, so nothing of the user's is ever merged over.
function shellUpdatable(shell) {
    return !!shell && shell.known && shell.repo === "ok" && shell.behind > 0 && shell.ahead === 0 && !shell.dirty
}

function shellCheckCommand(script, offline) {
    return offline ? [script, "check", "--offline"] : [script, "check"]
}

// Through a transient unit: the update ends in a shell restart, which would
// kill a child of the shell halfway through.
function shellUpdateCommand(script) {
    return ["systemd-run", "--user", "--quiet", "--collect", "--unit=buchhwin-shell-update",
            "--description=buchhwin-shell update", script, "apply"]
}

// ---- commands -----------------------------------------------------------------

function checkCommand(script, refresh, cacheOnly) {
    const argv = [script]
    if (cacheOnly) argv.push("--cache-only")
    else if (refresh) argv.push("--refresh")
    return argv
}

// Through scripts/launch-app.sh, like the launcher's applications: a unit
// named after Discover's entry, and the session's environment rather than
// the shell's own settings (two malloc arenas, no KDE platform theme).
function discoverCommand(launchScript) {
    return [launchScript, "org.kde.discover", "plasma-discover", "--mode", "update"]
}

// The page's terminals run as user services of these names
// (launch-terminal.sh --unit), not as children of the shell: a shell that
// stops cleanly ends its children, and the terminal with `pacman -Syu` in it
// went with every reload, deploy and shell update, pacman mid-transaction
// (16.10.). By name they can be watched, also by a shell started while one
// runs. They open in the session's terminal (Settings > Default apps) under
// a title that says what runs, and close by themselves once the command has
// succeeded; a failed one keeps its window with the exit status.
var UPGRADE_UNIT = "buchhwin-upgrade"
var FLATPAK_UNIT = "buchhwin-flatpak-update"

// Arch: Discover cannot install pacman's updates without PackageKit, and an
// upgrade on Arch is the whole system at once, in a terminal, by its user.
// An AUR helper upgrades the repositories and the AUR together; without one
// pacman asks for the password itself.
function terminalUpgradeCommand(terminalScript) {
    return [terminalScript, "--unit", UPGRADE_UNIT, "--hold-on-error", "--title", "System upgrade", "--", "sh", "-c",
            "if command -v paru >/dev/null 2>&1; then exec paru -Syu; "
            + "elif command -v yay >/dev/null 2>&1; then exec yay -Syu; "
            + "else exec sudo pacman -Syu; fi"]
}

// User installation only: system Flatpaks and packages go through Discover
// (polkit asks for the administrator password there).
function flatpakUpdateCommand(terminalScript) {
    return [terminalScript, "--unit", FLATPAK_UNIT, "--hold-on-error", "--title", "Flatpak update", "--",
            "flatpak", "update", "--user", "-y"]
}

// Prints "active" once when the unit runs, and returns once it no longer
// does; every 2 s, and only while a terminal is open.
function unitWatchCommand(unit) {
    return ["sh", "-c", "systemctl --user -q is-active \"$1\" || exit 0; echo active; "
            + "while systemctl --user -q is-active \"$1\"; do sleep 2; done", "sh", unit]
}

// The shell's own update ends in a restart and re-runs the installer: not
// while one of the terminals above is still at work (asked by hand, it says
// so; the automatic one tries again at its next check).
function shellUpdateAllowed(upgrading, flatpakUpdating) {
    return !upgrading && !flatpakUpdating
}

// ---- the shell's own foundation ---------------------------------------------------
// The packages the shell stands on: an upgrade of one changes the shell under
// the session that is running (Arch is rolling, and the shell leans on
// quirks of Quickshell 0.3.2 and Hyprland 0.56). Tagged "Shell core" in the
// list, with what to do after the upgrade. "session": the compositor and its
// libraries, which keep running the old version until the next login, while
// hyprctl and the portal are new; "shell": Quickshell and the Qt it is built
// on, loaded into the running shell. Names as Arch, Fedora (Copr) and openSUSE
// ship them, and the -git builds of the AUR.
var CORE_SESSION = /^(hyprland|xdg-desktop-portal-hyprland|aquamarine|hyprutils|hyprlang|hyprgraphics|hyprcursor)(-git)?$/
var CORE_SHELL = /^(quickshell(-git)?|qt6-(base|declarative|wayland)|qt6-qt(base|base-gui|declarative|wayland)|libQt6(Core|Gui|Qml|Quick|WaylandClient)6)$/

// "session", "shell" or "" for one package name.
function coreKind(name) {
    const text = String(name || "")
    if (CORE_SESSION.test(text)) return "session"
    if (CORE_SHELL.test(text)) return "shell"
    return ""
}

function corePackages(result) {
    return (result && result.packages || []).filter(item => coreKind(item.name).length > 0)
}

// The line under the package list when the upgrade holds some of them.
function coreNote(result) {
    const core = corePackages(result)
    if (!core.length) return ""
    const names = core.map(item => item.name)
    const shown = names.length > 4 ? names.slice(0, 4).join(", ") + " and " + (names.length - 4) + " more" : names.join(", ")
    const session = core.some(item => coreKind(item.name) === "session")
    return "Shell core in this upgrade: " + shown + ". "
        + (session ? "Log out and back in afterwards - the compositor keeps running the old version until then."
                   : "Restart the shell afterwards (Super+Ctrl+R).")
        + " The shell checks itself after its next start."
}

// ---- Arch: packages built on this machine ----------------------------------------
// updates-check.sh's @local-builds names the upgrades from the repositories
// whose installed package was built here (makepkg: unsigned, "Unknown
// Packager") - hyprland rebuilt with the shell's cursor patch, say. The
// upgrade replaces it with the repository's build and drops what it was built
// with. Said before the upgrade; nothing holds the package back (an IgnorePkg
// on hyprland would keep it against the new libraries of the next -Syu, and
// it would not start).

function localBuilds(result) {
    return (result && result.packages || []).filter(item => item.localBuild === true)
}

// "a", "a and b", "a, b and c".
function listText(names) {
    return names.length > 1 ? names.slice(0, -1).join(", ") + " and " + names[names.length - 1] : names.join("")
}

// Where the shell keeps the patch a self-built Hyprland carries (its README
// says what it fixes).
var HYPRLAND_PATCHES = "install/patches/Hyprland"

// The note above the package list when the upgrade replaces such a build.
function localBuildNote(result) {
    const names = localBuilds(result).map(item => item.name)
    if (!names.length) return ""
    const one = names.length === 1
    const note = listText(names) + (one ? " is your own build" : " are your own builds")
        + ", not the repository's. The upgrade replaces " + (one ? "it" : "them")
        + " with the repository's build, and anything your build changed (a patch, for example) is lost."
    return names.indexOf("hyprland") >= 0
        ? note + " To keep the shell's cursor patch, build the new hyprland again with the patches in "
          + HYPRLAND_PATCHES + " (in the shell's folder) after the upgrade and before you log out."
        : note
}

// ---- Arch: news before the upgrade, configuration files after it ---------------
// updates-check.sh adds two sections on Arch: @news, an AUR helper's -Pw (the
// Arch news newer than the installed packages - the ones that ask for a
// manual step before -Syu), and @pacnew, `pacdiff -o` (the .pacnew and
// .pacsave files upgrades left beside the system's own configuration).

// paru/yay -Pw: "2025-11-06 Title" at the start of a line, the article
// indented under it; "No new news" when there is none.
function parseNews(text) {
    const items = []
    let current = null
    for (const line of String(text || "").split("\n")) {
        const head = /^(\d{4}-\d{2}-\d{2})\s+(\S.*)$/.exec(line)
        if (head) {
            current = { date: head[1], title: head[2].trim().slice(0, 200), summary: "" }
            items.push(current)
            continue
        }
        if (current && !current.summary.length && /^\s+\S/.test(line)) {
            const summary = line.trim()
            current.summary = summary.length > 200 ? summary.slice(0, 197) + "…" : summary
        }
    }
    return items.slice(0, 10)
}

// pacdiff -o: one path per line.
function parsePacnew(text) {
    return String(text || "").split("\n").map(line => line.trim())
        .filter(line => /^\/[^\0]*\.(pacnew|pacsave|pacorig)(\.\d+)?$/.test(line) && line.length <= 512)
        .slice(0, 50)
}

function emptyExtras() {
    return { news: [], pacnew: [], newsKnown: false, pacnewKnown: false }
}

// The two sections of a report; a section the report does not have (another
// distribution, no AUR helper, a nested session) or one that failed is not
// known, and the last known answer stays (mergeExtras).
function parseExtras(text) {
    const sections = parseSections(text)
    const extras = emptyExtras()
    const news = sections["news"]
    // paru says "no new news" on stderr and exits 1 when there is none (seen
    // with paru 2.x on Arch); any other failure (offline, the feed
    // unreachable) keeps what was known.
    const newsErrors = sections["news-stderr"]
    const noNews = text => /no new news/i.test(text || "")
    if (news && (news.code === 0 || noNews(news.text) || (news.code === 1 && !!newsErrors && noNews(newsErrors.text)))) {
        extras.news = parseNews(news.text)
        extras.newsKnown = true
    }
    const pacnew = sections["pacnew"]
    if (pacnew && pacnew.code === 0) {
        extras.pacnew = parsePacnew(pacnew.text)
        extras.pacnewKnown = true
    }
    return extras
}

function mergeExtras(previous, next) {
    const before = previous || emptyExtras()
    return {
        news: next.newsKnown ? next.news : before.news || [],
        pacnew: next.pacnewKnown ? next.pacnew : before.pacnew || [],
        newsKnown: next.newsKnown || !!before.newsKnown,
        pacnewKnown: next.pacnewKnown || !!before.pacnewKnown
    }
}

// What updates.json keeps of them, checked like the rest of the state.
function cleanExtras(data) {
    const extras = emptyExtras()
    if (!data || typeof data !== "object") return extras
    if (Array.isArray(data.news))
        extras.news = data.news.filter(item => item && typeof item.date === "string" && typeof item.title === "string")
            .slice(0, 10).map(item => ({ date: item.date, title: item.title, summary: typeof item.summary === "string" ? item.summary : "" }))
    if (Array.isArray(data.pacnew)) extras.pacnew = parsePacnew(data.pacnew.join("\n"))
    extras.newsKnown = data.newsKnown === true
    extras.pacnewKnown = data.pacnewKnown === true
    return extras
}

function pacnewNote(paths) {
    const count = (paths || []).length
    if (!count) return ""
    return plural(count, "configuration file", "configuration files") + " from upgrades "
        + (count === 1 ? "waits" : "wait") + " beside the system's own (.pacnew). Look at them and merge what you want with:"
}

// -s: pacdiff runs as the user and asks sudo only to replace or remove a file.
var PACDIFF_COMMAND = "pacdiff -s"

// ---- the shell's own version (Settings > About) ----------------------------------
// `git log -10 --format=%h%x09%cs%x09%s` of the checkout the shell runs from:
// [{ hash, date, subject }], the newest first.
function parseLog(text) {
    return String(text || "").split("\n").map(line => line.split("\t")).filter(parts => parts.length >= 3
        && /^[0-9a-f]{4,40}$/.test(parts[0]) && /^\d{4}-\d{2}-\d{2}$/.test(parts[1]))
        .map(parts => ({ hash: parts[0], date: parts[1], subject: parts.slice(2).join("\t").trim() }))
}

// "2026-10-19" → "Oct 19" ("Oct 19 2025" in another year than `now`'s): the
// order checkedText writes a day in, on this page and beside it.
function shortDate(day, now) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day || ""))
    if (!match) return ""
    const month = MONTHS[parseInt(match[2], 10) - 1]
    if (!month) return ""
    const text = month + " " + parseInt(match[3], 10)
    return now && new Date(now).getFullYear() !== parseInt(match[1], 10) ? text + " " + match[1] : text
}

// "e5a68ce · Oct 19", or "" for a checkout git does not know.
function versionLine(commits, now) {
    const head = (commits || [])[0]
    if (!head) return ""
    const date = shortDate(head.date, now)
    return head.hash + (date.length ? " · " + date : "")
}

function logCommand(dir) {
    return ["git", "-C", String(dir || "."), "log", "-10", "--format=%h%x09%cs%x09%s"]
}
