.pragma library

// Pure helpers for the settings sidebar (shell/settings/SettingsPanel.qml):
// page list, groups, search filtering and keyboard navigation.

// Page ids are used by IPC `settings open PAGE`, the launcher `@` entries and
// the page file names (id "lockScreen" → pages/LockScreenPage.qml). The
// subtitle belongs here with the rest of a page's metadata: it used to be a
// hard-wired ternary chain in SettingsPanel, where 12 of 23 pages had none and
// a new page silently got none.
const PAGES = [
    { id: "appearance", subtitle: "Customize the look and behavior of buchhwin-shell", title: "Appearance", icon: "󰏘", keywords: "theme light dark accent color font panel background opacity individual windows transparency blur corners border gaps animation cursor mouse darstellung hell dunkel akzent farbe schrift transparenz unschärfe ecken rahmen abstand mauszeiger apps kde gtk plasma color scheme programme" },
    { id: "wallpaper", subtitle: "Choose a wallpaper or set up a slideshow", title: "Wallpaper", icon: "󰸉", keywords: "wallpaper slideshow folder background hintergrundbild diashow ordner" },
    { id: "lockScreen", subtitle: "The lock screen's look, its extras and fingerprint unlock", title: "Lock Screen", icon: "󰌾", keywords: "lock screen password clock blur avatar media power buttons fingerprint fprintd reader enroll sperrbildschirm sperren passwort fingerabdruck" },
    { id: "profiles", icon: "󰒓", subtitle: "Profiles and the five modes each one has", title: "Profiles", keywords: "profile profiles mode modes minimal work gaming laptop docked switch automatic duplicate reset rename remove factory state profil profile modus modi wechseln automatisch duplizieren zurücksetzen umbenennen entfernen werkszustand" },
    { id: "desktop", icon: "󱂵", subtitle: "Clock, clipboard, screen recording and removable drives", title: "Desktop Extras", keywords: "clock hints indicators osd volume brightness clipboard history screen recording video removable drives usb stick sd card external disk uhr hinweise anzeige zwischenablage aufnahme laufwerke" },
    { id: "widgets", subtitle: "Choose the desktop mode and arrange the widgets on your wallpaper", title: "Widgets", icon: "󰕰", keywords: "widgets desktop mode layout editor clock date weather calendar arrange move group style add remove edit modus oberfläche anordnen verschieben gruppieren stil hinzufügen entfernen bearbeiten" },
    { id: "bar", subtitle: "Choose the desktop mode, workspaces and build your own bar", title: "Bar & Notch", icon: "󰘔", keywords: "bar pills notch island desktop mode panel top leiste modus oben kerbe insel workspaces arbeitsflächen" },
    { id: "notifications", subtitle: "Popups, history and Do Not Disturb", title: "Notifications", icon: "󰂚", keywords: "dnd do not disturb popup benachrichtigungen nicht stören" },
    { id: "launcher", subtitle: "Web search and file search in the launcher", title: "Launcher", icon: "󰍉", keywords: "launcher search web engine duckduckgo google startpage wikipedia url address files plocate suche suchmaschine web adresse dateien starter" },
    { id: "shortcuts", subtitle: "Key combinations for the shell, windows and your own apps and commands", title: "Shortcuts", icon: "󰥻", keywords: "shortcuts keyboard shortcuts hotkeys keybindings key bindings keys custom command super tastenkürzel tastenkombination kurzbefehle tastatur" },
    { id: "weather", subtitle: "Location and display for the dashboard and weather widget", title: "Weather", icon: "󰖐", keywords: "place city location temperature open-meteo wetter ort stadt standort temperatur" },
    { id: "calendar", subtitle: "Events from the KDE calendars in the dashboard and next to the clock", title: "Calendar", icon: "󰸗", keywords: "events google akonadi merkuro kalender termine" },
    { id: "network", subtitle: "Wi-Fi, hotspot and VPN connections", title: "Network", icon: "󰤨", keywords: "wi-fi wifi vpn netzwerk wlan" },
    { id: "bluetooth", subtitle: "Pair and manage Bluetooth devices", title: "Bluetooth", icon: "󰂯", keywords: "devices pair geräte koppeln" },
    { id: "kdeConnect", subtitle: "Pair your phone with KDE Connect to share files, the clipboard and notifications", title: "Phone", icon: "󰄜", keywords: "kde connect phone android iphone smartphone tablet pair ping find my phone ring send files share clipboard battery handy telefon koppeln dateien senden zwischenablage akku" },
    { id: "displays", subtitle: "Arrangement, resolution, refresh rate and scaling", title: "Displays", icon: "󰍹", keywords: "display monitor resolution hz scaling monitore auflösung skalierung" },
    { id: "audio", subtitle: "Output, input and the volume of each app", title: "Audio", icon: "󰕾", keywords: "sound volume microphone ton lautstärke mikrofon" },
    { id: "input", subtitle: "Keyboard, touchpad, mouse and touchpad gestures", title: "Input", icon: "󰌌", keywords: "keyboard layout touchpad mouse pointer scrolling repeat rate gestures swipe pinch eingabe tastatur maus zeiger scrollen wiederholrate gesten wischen" },
    { id: "power", subtitle: "Battery and mains behavior, idle, sleep and the lid", title: "Power", icon: "󰁹", keywords: "battery charger plugged in ac profile screen off lock sleep lid close stay awake energie akku netzteil profil bildschirm aus sperren bereitschaft deckel zuklappen wach" },
    { id: "terminal", subtitle: "Kitty, Starship prompt and Fastfetch for terminals in this session", title: "Terminal", icon: "󰆍", keywords: "kitty starship prompt zsh fastfetch font cursor transparency schrift transparenz" },
    { id: "defaultApps", subtitle: "Apps for links, files and the app hotkeys", title: "Default Apps", icon: "󰀻", keywords: "default applications browser email file manager terminal text editor images pdf video music archives open with mime standard anwendungen standardprogramme öffnen mit" },
    { id: "autostart", subtitle: "Apps and services that start when you log in", title: "Autostart", icon: "󰒲", keywords: "startup login apps kde connect start anmelden" },
    { id: "accounts", subtitle: "Online accounts for calendars, contacts and mail", title: "Accounts", icon: "󰀉", keywords: "accounts account online google nextcloud caldav carddav dav groupware ical file imap pop3 mail email contacts calendar akonadi kde pim sync add remove wizard konten konto zugang hinzufügen entfernen synchronisieren kalender kontakte e-mail postfach" },
    { id: "updates", subtitle: "System packages and Flatpaks that can be updated", title: "Updates", icon: "󰚰", keywords: "updates upgrade software packages dnf flatpak discover security check aktualisierungen pakete sicherheit" },
    { id: "login", subtitle: "How the login screen looks before you are signed in", title: "Login Screen", icon: "󰍂", keywords: "login screen sddm greeter theme background blur accent font date anmeldung anmeldebildschirm hintergrund akzent schrift datum" },
    { id: "about", subtitle: "This session, the system and the versions it runs on", title: "About", icon: "󰋼", keywords: "system fedora version info" }
]

// Sidebar sections in display order; every page id belongs to exactly one.
const GROUPS = [
    // Lock Screen and Login Screen are the same kind of thing - how a screen
    // looks before you are in - so they sit together rather than one here and
    // one under System.
    { key: "personalization", title: "Personalization", pages: ["appearance", "wallpaper", "lockScreen", "login"] },
    { key: "desktop", title: "Desktop", pages: ["profiles", "widgets", "bar", "desktop", "notifications", "launcher", "shortcuts"] },
    { key: "dashboard", title: "Dashboard", pages: ["weather", "calendar"] },
    { key: "connectivity", title: "Connectivity", pages: ["network", "bluetooth", "kdeConnect"] },
    { key: "devices", title: "Devices", pages: ["displays", "audio", "input", "power"] },
    { key: "apps", title: "Apps", pages: ["terminal", "defaultApps", "autostart"] },
    { key: "system", title: "System", pages: ["accounts", "updates", "about"] }
]

function pageById(id, pages) {
    const list = pages || PAGES
    return list.find(page => page.id === id) || null
}

// A page matches when every word of the query appears in its title, keywords
// or group title (case-insensitive). An empty query matches everything.
function matches(page, groupTitle, query) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(word => word.length > 0)
    if (!words.length) return true
    const haystack = (page.title + " " + (page.keywords || "") + " " + (groupTitle || "")).toLowerCase()
    return words.every(word => haystack.includes(word))
}

// Flat sidebar rows: { kind: "heading", key, title } before the pages of each
// group, { kind: "page", id, title, icon, group } per page. Groups without a
// matching page get no heading; unknown page ids in a group are skipped.
function rows(query, groups, pages) {
    const groupList = groups || GROUPS
    const pageList = pages || PAGES
    const result = []
    for (const group of groupList) {
        const matching = group.pages
            .map(id => pageById(id, pageList))
            .filter(page => page !== null && matches(page, group.title, query))
        if (!matching.length) continue
        result.push({ kind: "heading", key: group.key, title: group.title })
        // `first` and `last` let the sidebar draw one card behind each group,
        // the same surface the page's own sections use on the right.
        matching.forEach((page, index) => result.push({
            kind: "page", id: page.id, title: page.title, icon: page.icon, group: group.key,
            first: index === 0, last: index === matching.length - 1
        }))
    }
    return result
}

// Page ids of the rows in display order (headings skipped).
function pageIds(rowList) {
    return (rowList || []).filter(row => row.kind === "page").map(row => row.id)
}

// Page id `delta` steps from `current` among the visible pages, clamped to the
// ends. An unknown current page starts at the first (down) or last (up) page.
function step(rowList, current, delta) {
    const ids = pageIds(rowList)
    if (!ids.length) return ""
    const index = ids.indexOf(current)
    if (index < 0) return delta < 0 ? ids[ids.length - 1] : ids[0]
    return ids[Math.max(0, Math.min(ids.length - 1, index + delta))]
}

// Page ids that are in no group or in more than one (for the unit test).
function ungroupedPages(groups, pages) {
    const counts = {}
    for (const group of groups || GROUPS)
        for (const id of group.pages) counts[id] = (counts[id] || 0) + 1
    return (pages || PAGES).filter(page => counts[page.id] !== 1).map(page => page.id)
}
