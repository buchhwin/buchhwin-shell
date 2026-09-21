import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/accounts/AccountsLogic.js" as A

ShellRoot {
    // Synthetic snapshot in the format of scripts/accounts-status.sh; the
    // names are invented, no real account ever appears in the repository.
    FileView { id: sample; path: Qt.resolvedUrl("../fixtures/accounts-status.txt").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // busctl JSON
        T.eq(A.busValue("{\"type\":\"s\",\"data\":[\"Mail\"]}"), "Mail", "string result")
        T.eq(A.busValue("{\"type\":\"as\",\"data\":[[\"Resource\",\"Unique\"]]}"), ["Resource", "Unique"], "string list result")
        T.eq(A.busValue("{\"type\":\"b\",\"data\":[false]}"), false, "boolean result")
        T.eq(A.busValue("Call failed: no such method"), undefined, "errors ignored")
        T.eq(A.busValue(""), undefined, "empty output ignored")
        T.eq(A.fields(["name {\"type\":\"s\",\"data\":[\"A\"]}", "broken", "Name {\"type\":\"s\",\"data\":[\"B\"]}"]),
             { name: "A" }, "only lowercase key lines with JSON")

        // Ids reach D-Bus and a command line as their own argument.
        T.ok(A.validId("akonadi_google_resource_0") && !A.validId("bad/id") && !A.validId("--help") && !A.validId(""),
             "instance ids are validated")

        // Snapshot
        const status = A.parseStatus(sample.text())
        T.ok(status.known && status.server, "Akonadi is running")
        T.eq(status.tools, ["kaccounts", "systemsettings", "accountwizard"], "unknown wizards dropped")
        T.eq(status.accounts.length, 7, "only resources, invalid ids skipped")
        T.eq(status.accounts.map(item => item.id),
             ["akonadi_ical_resource_0", "akonadi_davgroupware_resource_0", "akonadi_contacts_resource_0",
              "akonadi_imap_resource_0", "akonadi_unknown_resource_0", "akonadi_google_resource_0",
              "akonadi_birthdays_resource"],
             "errors first, then offline, then by name, built-in last")

        const google = status.accounts.find(item => item.id === "akonadi_google_resource_0")
        T.eq(google.name, "Test Account (Google)", "instance name")
        T.eq(google.typeName, "Google Groupware", "type name from the agent type")
        T.eq(google.iconName, "account-google", "freedesktop icon name")
        T.eq(google.kinds, ["calendar", "contacts"], "content from the mime types")
        T.eq(A.contentText(google), "Calendar · Contacts", "content text")
        T.eq(A.statusText(google), "Syncing… 42%", "running with progress")
        T.eq(A.statusTone(google), "busy", "running tone")
        T.eq(A.icon(google), "󰸗", "calendar icon")
        T.eq(A.subtitle(google, 0, 0), "Google Groupware · Calendar · Contacts · Fetching calendars", "subtitle without a sync time")

        const dav = status.accounts.find(item => item.id === "akonadi_davgroupware_resource_0")
        T.eq([A.statusText(dav), A.statusTone(dav)], ["Offline", "muted"], "offline beats the status code")
        T.eq(A.subtitle(dav, 0, 0), "DAV groupware resource · Calendar · Contacts", "a repeated status word is dropped")

        const ical = status.accounts.find(item => item.id === "akonadi_ical_resource_0")
        T.eq([A.statusText(ical), A.statusTone(ical)], ["Error", "error"], "broken resource")

        const imap = status.accounts.find(item => item.id === "akonadi_imap_resource_0")
        T.eq([A.statusText(imap), A.statusTone(imap), A.icon(imap)], ["Ready", "ok", "󰇮"], "idle mail account")

        const contacts = status.accounts.find(item => item.id === "akonadi_contacts_resource_0")
        T.eq(contacts.name, "Personal Contacts", "an empty name falls back to the type name")
        T.eq([A.statusText(contacts), A.icon(contacts)], ["Not configured", "󰀄"], "unconfigured contacts account")

        const unknown = status.accounts.find(item => item.id === "akonadi_unknown_resource_0")
        T.eq([unknown.kinds, A.icon(unknown), A.subtitle(unknown, 0, 0)], [[], "󰒓", "akonadi_unknown_resource"],
             "a type without metadata still shows a row")

        T.ok(status.accounts.find(item => item.id === "akonadi_birthdays_resource").builtIn, "Unique resources are built-in")
        T.ok(!google.builtIn, "added accounts are not built-in")

        // Groups
        T.eq(A.groups(status.accounts).map(group => group.key + ":" + group.accounts.length),
             ["mail:1", "calendar:4", "contacts:1", "other:1"], "grouped by content, empty groups dropped")
        T.eq(A.groups(status.accounts)[1].title, "Calendars", "group title")
        T.eq(A.groups([]), [], "no accounts, no groups")

        T.eq(A.summary(status), "7 accounts · 1 with an error · 1 offline", "summary counts only")
        T.eq(A.summary(A.parseStatus("@server stopped\n")), "KDE PIM (Akonadi) is not running", "server stopped")
        T.eq(A.summary(A.parseStatus("")), "Checking accounts…", "unknown before the first run")
        T.eq(A.summary(A.parseStatus("@server running\n")), "No accounts yet", "running without accounts")
        T.eq(A.syncing(status.accounts), 1, "one account is syncing")

        // Last sync
        const now = 1758000000000
        T.eq(A.lastSyncText(now - 20 * 1000, now), "just now", "seconds")
        T.eq(A.lastSyncText(now - 5 * 60 * 1000, now), "5 min ago", "minutes")
        T.eq(A.lastSyncText(now - 60 * 60 * 1000, now), "1 hour ago", "one hour")
        T.eq(A.lastSyncText(now - 5 * 60 * 60 * 1000, now), "5 hours ago", "hours")
        T.eq(A.lastSyncText(now - 26 * 60 * 60 * 1000, now), "yesterday", "one day")
        T.eq(A.lastSyncText(now - 3 * 24 * 60 * 60 * 1000, now), "3 days ago", "days")
        T.eq(A.lastSyncText(0, now), "", "never synchronized")
        T.eq(A.lastSyncText(now, 0), "", "no reference time")
        T.eq(A.subtitle(imap, now - 5 * 60 * 1000, now), "IMAP E-Mail Server · Mail · Last sync 5 min ago", "subtitle with a sync time")

        // Commands
        const id = "akonadi_google_resource_0"
        const manager = ["busctl", "--user", "--auto-start=no", "call", "org.freedesktop.Akonadi.Control",
                         "/AgentManager", "org.freedesktop.Akonadi.AgentManager"]
        T.eq(A.command("sync", id), manager.concat(["agentInstanceSynchronize", "s", id]), "sync argv")
        T.eq(A.command("configure", id), manager.concat(["agentInstanceConfigure", "sx", id, "0"]), "configure argv")
        T.eq(A.command("remove", id), manager.concat(["removeAgentInstance", "s", id]), "remove argv")
        T.eq(A.command("sync", "akonadi_x; rm -rf ~"), null, "shell-like id rejected")
        T.eq(A.command("sync", "--help"), null, "option-like id rejected")
        T.eq(A.command("createAgentInstance", id), null, "unknown action")
        T.eq(A.commandText(A.command("sync", id)), manager.concat(["agentInstanceSynchronize", "s", id]).join(" "), "dry-run line")
        T.eq(A.commandText(["kcmshell6", "a b"]), "kcmshell6 'a b'", "quoted argument")

        // Wizards
        T.eq(A.addOptions(status.tools).map(item => item.tool), ["kaccounts", "accountwizard"],
             "systemsettings duplicate dropped")
        T.eq(A.addOptions(["systemsettings", "accountwizard"]).map(item => item.label),
             ["Online accounts…", "Mail & groupware…"], "systemsettings stands in for kcmshell6")
        T.eq(A.addOptions([]), [], "no wizard installed")
        T.eq(A.addCommand("kaccounts"), ["kcmshell6", "kcm_kaccounts"], "online accounts wizard")
        T.eq(A.addCommand("accountwizard"), ["accountwizard"], "mail and groupware wizard")
        T.eq(A.addCommand("hasOwnProperty"), null, "inherited names are not wizards")
        T.eq(A.addCommand("rm"), null, "unknown wizard")

        // Results
        T.eq(A.parseResult("ok\n@exit 0\n"), { code: 0, output: "ok" }, "exit code split off")
        T.eq(A.parseResult("killed"), { code: -1, output: "killed" }, "missing exit code")
        T.eq(A.wrap(["busctl", "x"]).slice(0, 2), ["sh", "-c"], "wrapped for the exit code")
        T.eq(A.wrap(["busctl", "x"]).slice(-2), ["busctl", "x"], "argv stays separate")
        T.eq(A.errorText("sync", "Call failed: Connection timed out"), "KDE PIM (Akonadi) did not answer", "timeout message")
        T.eq(A.errorText("remove", "Call failed: some detail with \"Test Account\""), "The account could not be removed",
             "error messages never repeat the output")
        T.eq(A.successText("sync"), "Synchronizing…", "success message")
        T.finish("AccountsTest")
    }
}
