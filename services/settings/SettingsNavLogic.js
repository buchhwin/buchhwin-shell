.pragma library

// Pure helpers for the settings sidebar (shell/settings/SettingsPanel.qml):
// page list, groups, search filtering and keyboard navigation.

// Page ids are used by IPC `settings open PAGE`, the launcher `@` entries and
// the page file names (id "lockScreen" → pages/LockScreenPage.qml). The
// subtitle belongs here with the rest of a page's metadata: it used to be a
// hard-wired ternary chain in SettingsPanel, where 12 of 23 pages had none and
// a new page silently got none.
const PAGES = [
    { id: "appearance", subtitle: "Customize the look and behavior of buchhwin-shell", title: "Appearance", icon: "󰏘", keywords: "theme light dark accent color font panel background opacity individual windows transparency blur corners border gaps animation cursor mouse darstellung hell dunkel akzent farbe schrift transparenz unschärfe ecken rahmen abstand mauszeiger apps kde gtk plasma color scheme programme mode night nightlight blue temperature hours schedule panels effects dim behind follow restore colors logout screen edge round borders width animations speed interface monospace text size dunkelmodus hellmodus nachtlicht blaulicht farbtemperatur zeitplan effekte abdunkeln wiederherstellen abmelden bildschirmrand rahmenbreite animationen geschwindigkeit oberfläche textgröße schriftgröße größe icons restart symbole neustart" },
    { id: "wallpaper", subtitle: "Choose a wallpaper or set up a slideshow", title: "Wallpaper", icon: "󰸉", keywords: "wallpaper slideshow folder background hintergrundbild diashow ordner current images interval order random favorites favourites aktuell bilder intervall reihenfolge zufällig favoriten" },
    { id: "lockScreen", subtitle: "The lock screen's look, its extras and fingerprint unlock", title: "Lock screen", icon: "󰌾", keywords: "lock screen password clock blur avatar media power buttons fingerprint fprintd reader enroll sperrbildschirm sperren passwort fingerabdruck corners default arrangement layout ecken anordnung standard" },
    { id: "profiles", icon: "\u{f05d2}", subtitle: "Profiles and the five modes each one has", title: "Profiles", keywords: "profile profiles mode modes minimal work gaming laptop docked desk switch automatic duplicate reset rename remove factory state profil profile modus modi wechseln automatisch duplizieren zurücksetzen umbenennen entfernen werkszustand automatically" }, // Icons.profile
    { id: "desktop", icon: "󱂵", subtitle: "Clock, clipboard, screen recording and removable drives", title: "Desktop extras", keywords: "clock hints indicators osd volume brightness clipboard history screen recording video removable drives usb stick sd card external disk uhr hinweise anzeige zwischenablage aufnahme laufwerke time format 12 hours 24 automatically folder frame rate fps notify connected save sound microphone mtp encrypted zeitformat uhrzeit ordner bildrate ton benachrichtigen verbunden speichern automatisch forget logout entries vergessen abmelden einträge" },
    { id: "widgets", subtitle: "Choose the desktop mode and arrange the widgets on your wallpaper", title: "Widgets", icon: "󰕰", keywords: "widgets desktop mode layout editor clock date weather calendar arrange move group style add remove edit modus oberfläche anordnen verschieben gruppieren stil hinzufügen entfernen bearbeiten hidden ausgeblendet" },
    { id: "dock", subtitle: "Pinned and running apps at the edge of the screen", title: "Dock", icon: "\u{f1888}", keywords: "dock taskbar task bar pinned pins running apps favorites favourites autohide auto-hide intellihide hide magnification zoom edge taskleiste angeheftet laufende programme ausblenden vergrößerung rand start menu start button startmenü startmenue startknopf startschaltfläche saturn behavior visibility position width icon size distance magnify pointer presets layout look transparency keyboard verhalten sichtbarkeit breite symbolgröße abstand voreinstellungen tastatur transparenz" }, // Icons.dock
    { id: "bar", subtitle: "Choose the desktop mode, workspaces and build your own bar", title: "Bar & notch", icon: "󰘔", keywords: "bar pills notch island desktop mode panel top leiste modus oben kerbe insel workspaces arbeitsflächen keep empty close desktops offen halten schließen edge position style size preset events fullscreen hidden level monitors notifications number panels reserve space windows exclusive track changes volume brightness rand stil größe vollbild ausgeblendet monitore benachrichtigungen anzahl platz reservieren lautstärke helligkeit" },
    { id: "notifications", subtitle: "Popups, history and Do Not Disturb", title: "Notifications", icon: "󰂚", keywords: "dnd do not disturb popup benachrichtigungen nicht stören duration ends mute automatically fullscreen gaming games steam gamescope history dauer stumm stummschalten vollbild spiele automatisch verlauf apps focused fokussiert" },
    // Its pinned apps are the start menu's "Pinned" grid as well ("Pin to
    // Start"), so the start menu's words find it too, beside the Dock page
    // with its own pins.
    { id: "launcher", subtitle: "Modes, pinned apps for the launcher and the start menu, web and file search", title: "Launcher", icon: "󰍉", keywords: "launcher search web engine duckduckgo google startpage wikipedia url address files plocate pin pinned pins pin to start start menu startmenü startmenue angeheftet anheften suche suchmaschine web adresse dateien starter" }, // Icons.search
    { id: "shortcuts", subtitle: "Key combinations for the shell, windows and your own apps and commands", title: "Shortcuts", icon: "󰥻", keywords: "shortcuts keyboard shortcuts hotkeys keybindings key bindings keys custom command super tastenkürzel tastenkombination kurzbefehle tastatur action touchpad gestures aktion gesten" },
    { id: "weather", subtitle: "Location and display for the dashboard and weather widget", title: "Weather", icon: "󰖐", keywords: "place city location temperature open-meteo dashboard wetter ort stadt standort temperatur detect unit units fahrenheit celsius refresh erkennen einheit aktualisieren" },
    { id: "calendar", subtitle: "Events from the KDE calendars in the dashboard and next to the clock", title: "Calendar", icon: "󰸗", keywords: "events google akonadi merkuro dashboard kalender termine colors source upcoming hint lead time reminder farben quelle anstehend hinweis vorlaufzeit erinnerung" },
    { id: "network", subtitle: "Wi-Fi, hotspot and VPN connections", title: "Network", icon: "󰤨", keywords: "wi-fi wifi vpn netzwerk wlan ethernet cable lan ip address active details status wireguard kabel ip-adresse aktiv" },
    { id: "bluetooth", subtitle: "Pair and manage Bluetooth devices", title: "Bluetooth", icon: "󰂯", keywords: "devices pair geräte koppeln nearby visible discoverable sichtbar nähe" },
    { id: "kdeConnect", subtitle: "Pair your phone with KDE Connect to share files, the clipboard and notifications", title: "Phone", icon: "󰄜", keywords: "kde connect phone android iphone smartphone tablet pair ping find my phone ring send files share clipboard battery handy telefon koppeln dateien senden zwischenablage akku devices available requests geräte verfügbar anfragen" },
    { id: "displays", subtitle: "Arrangement, resolution, refresh rate and scaling", title: "Displays", icon: "󰍹", keywords: "display monitor resolution hz scaling monitore auflösung skalierung enabled scale orientation rotation rotate portrait adaptive sync vrr freesync position x11 xwayland sharp applications aktiviert drehung ausrichtung hochformat bildwiederholrate scharf anwendungen" },
    { id: "audio", subtitle: "Output, input and the volume of each app", title: "Audio", icon: "󰕾", keywords: "sound volume microphone ton lautstärke mikrofon applications apps channels details level meter pipewire name anwendungen kanäle pegel" },
    { id: "input", subtitle: "Keyboard, touchpad, mouse and touchpad gestures", title: "Input", icon: "󰌌", keywords: "keyboard layout touchpad mouse pointer scrolling repeat rate gestures swipe pinch eingabe tastatur maus zeiger scrollen wiederholrate gesten wischen speed acceleration sensitivity variant delay natural tap click disable typing direction create workspace end match vs code geschwindigkeit beschleunigung empfindlichkeit variante verzögerung natürliches antippen klicken deaktivieren richtung arbeitsfläche" },
    { id: "power", subtitle: "Battery and mains behavior, idle, sleep and the lid", title: "Power", icon: "󰁹", keywords: "battery charger plugged in ac profile screen off lock sleep lid close stay awake energie akku netzteil profil bildschirm aus sperren bereitschaft deckel zuklappen wach status colors colours green accent charging vpn statusfarben grün akzent laden low warnings warn dim closes suspend idle hibernate performance balanced power saver schwach warnung abdunkeln ruhezustand leerlauf leistung locked gesperrt" },
    { id: "terminal", subtitle: "Starship prompt, Fastfetch, the look of kitty and Alacritty's windows", title: "Terminal", icon: "󰆍", keywords: "kitty alacritty daemon starship prompt zsh fastfetch font cursor transparency fast windows schrift transparenz schnell fenster opacity blink blinking trail clock format colors configuration custom directory depth duration git repository preview image size logo modules padding process shell symbols blinken farben konfiguration verzeichnistiefe dauer vorschau bildgröße module innenabstand symbole" },
    { id: "defaultApps", subtitle: "Apps for links, files and the app hotkeys", title: "Default apps", icon: "󰀻", keywords: "default applications browser email file manager terminal text editor images pdf video music archives open with mime standard anwendungen standardprogramme öffnen mit" }, // Icons.apps
    { id: "autostart", subtitle: "Apps and services that start when you log in", title: "Autostart", icon: "\u{f14de}", keywords: "startup login apps kde connect start anmelden system standard xdg" }, // Icons.autostart
    { id: "accounts", subtitle: "Online accounts for calendars, contacts and mail", title: "Accounts", icon: "󰀉", keywords: "accounts account online google nextcloud caldav carddav dav groupware ical file imap pop3 mail email contacts calendar akonadi kde pim sync add remove wizard konten konto zugang hinzufügen entfernen synchronisieren kalender kontakte e-mail postfach" },
    { id: "updates", subtitle: "System packages and Flatpaks that can be updated", title: "Updates", icon: "󰚰", keywords: "updates upgrade software packages dnf zypper pacman aur paru flatpak discover security check aktualisierungen pakete sicherheit automatically install notify shell automatisch installieren benachrichtigen" },
    { id: "login", subtitle: "How the login screen looks before you are signed in", title: "Login screen", icon: "󰍂", keywords: "login screen sddm greeter theme background blur accent font date anmeldung anmeldebildschirm hintergrund akzent schrift datum wallpaper colors family hintergrundbild farbe schriftart" },
    { id: "about", subtitle: "This session, the system and the versions it runs on", title: "About", icon: "󰋼", keywords: "system fedora opensuse leap arch version info buchhwin-shell tour welcome rundgang willkommen" } // Icons.info
]

// Sidebar sections in display order; every page id belongs to exactly one.
const GROUPS = [
    // Lock screen and Login screen are the same kind of thing - how a screen
    // looks before you are in - so they sit together rather than one here and
    // one under System.
    { key: "personalization", title: "Personalization", pages: ["appearance", "wallpaper", "lockScreen", "login"] },
    // Bar & notch before Widgets: both shipped profiles run the notch, so the
    // bar page is the one in use and Widgets mostly says "hidden" there.
    { key: "desktop", title: "Desktop", pages: ["profiles", "bar", "widgets", "dock", "desktop", "notifications", "launcher", "shortcuts"] },
    { key: "connectivity", title: "Connectivity", pages: ["network", "bluetooth", "kdeConnect"] },
    { key: "devices", title: "Devices", pages: ["displays", "audio", "input", "power"] },
    { key: "apps", title: "Apps", pages: ["terminal", "defaultApps", "autostart"] },
    // Weather and calendar are set once and feed more than the dashboard (the
    // notch, widgets, the clock's hints), so they sit low and are not called
    // "Dashboard"; the word stays in their keywords. Calendar ends up next to
    // Accounts, where its calendars come from. The key stays for anything
    // that remembered it.
    { key: "dashboard", title: "Calendar & weather", pages: ["weather", "calendar"] },
    { key: "system", title: "System", pages: ["accounts", "updates", "about"] }
]

function pageById(id, pages) {
    const list = pages || PAGES
    return list.find(page => page.id === id) || null
}

// A page matches when every word of the query appears in its title,
// subtitle, keywords or group title (case-insensitive). An empty query
// matches everything. The subtitle counts as well: Network's says "hotspot"
// and Displays' "refresh rate", and neither found its page. The search never
// sees a page itself, so the keywords carry the words of its sections and
// rows (tests/python/settings_nav_test.py fails on one they miss).
function matches(page, groupTitle, query) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(word => word.length > 0)
    if (!words.length) return true
    const haystack = (page.title + " " + (page.subtitle || "") + " " + (page.keywords || "") + " " + (groupTitle || "")).toLowerCase()
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

// A row's key in the sidebar: "h:" and the group for a heading, "p:" and the
// id for a page. The sidebar's Repeater runs over these strings rather than
// over the rows themselves: `rows()` builds new objects for every query, and
// a Repeater over them built all 34 sidebar rows again on every keystroke
// (about 30 ms). Strings compare by value, so narrowing the search only
// takes rows away and widening it adds them (testing.md pitfall 76).
function rowKey(row) {
    return row.kind === "heading" ? "h:" + row.key : "p:" + row.id
}

// The rows by their keys, for a delegate that has only its key.
function rowsByKey(rowList) {
    const byKey = {}
    for (const row of rowList || []) byKey[rowKey(row)] = row
    return byKey
}

// The index in `rowList` of the heading over the page `id` (the first row of
// its group), -1 when the page is not listed. Revealing a page scrolls to
// that heading where it fits, so the group's card is not cut square under
// the search field with its name above the fold.
function headingIndex(rowList, id) {
    const list = rowList || []
    const index = list.findIndex(row => row.kind === "page" && row.id === id)
    for (let at = index; at >= 0; --at)
        if (list[at].kind === "heading") return at
    return -1
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
