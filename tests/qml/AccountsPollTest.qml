import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/accounts/AccountsLogic.js" as A

// Settings > Accounts reads the whole snapshot as it opens and after every
// action, and every 10 s only the accounts' status (accounts-status.sh
// --status ID…), laid over the last whole snapshot. A poll that cannot be laid
// over it - the server stopped, an agent came or went, a broken answer - asks
// for the whole snapshot again. Invented names only.
ShellRoot {
    function json(type, value) { return JSON.stringify({ type: type, data: [value] }) }
    function instance(id, name, status, online) {
        return ["@instance " + id, "name " + json("s", name), "status " + json("i", status),
                "message " + json("s", status === 1 ? "Fetching mail" : "Ready"), "online " + json("b", online),
                "progress " + json("u", status === 1 ? 40 : 0)]
    }

    Component.onCompleted: {
        const whole = ["@tools kaccounts", "@server running",
            "@agents akonadi_indexing_agent akonadi_imap_resource_0 akonadi_ical_resource_0",
            "@type akonadi_imap_resource", "name " + json("s", "IMAP E-Mail Server"), "icon " + json("s", "network-server"),
            "mime " + JSON.stringify({ type: "as", data: [["message/rfc822"]] }),
            "caps " + JSON.stringify({ type: "as", data: [["Resource"]] }),
            "@type akonadi_ical_resource", "name " + json("s", "iCal Calendar File"), "icon " + json("s", "text-calendar"),
            "mime " + JSON.stringify({ type: "as", data: [["text/calendar"]] }),
            "caps " + JSON.stringify({ type: "as", data: [["Resource"]] })]
            .concat(instance("akonadi_imap_resource_0", "Work mail", 0, true), ["type " + json("s", "akonadi_imap_resource")])
            .concat(instance("akonadi_ical_resource_0", "Local calendar", 0, true), ["type " + json("s", "akonadi_ical_resource")])
            .join("\n")
        const status = A.parseStatus(whole)
        T.eq(status.agents, ["akonadi_ical_resource_0", "akonadi_imap_resource_0", "akonadi_indexing_agent"],
             "the agents of a whole snapshot, sorted")
        T.ok(A.canPoll(status), "a running server with listed agents can be polled")
        T.eq(A.pollIds(status).slice().sort(), ["akonadi_ical_resource_0", "akonadi_imap_resource_0"],
             "the poll asks for the accounts shown")
        T.eq(A.parseStatus("@server running\n").agents, null, "a snapshot without @agents lists none")
        T.ok(!A.canPoll(A.parseStatus("@server running\n")), "and is not polled (the sample, an older helper)")
        T.ok(!A.canPoll(A.parseStatus("@server stopped\n")), "a stopped server is not polled")
        T.ok(!A.canPoll(A.parseStatus("")), "nor an unknown state")

        // The status poll: a sync starts on the mail account.
        const poll = ["@server running", "@agents akonadi_imap_resource_0 akonadi_ical_resource_0 akonadi_indexing_agent"]
            .concat(instance("akonadi_imap_resource_0", "Work mail", 1, true))
            .concat(instance("akonadi_ical_resource_0", "Local calendar", 0, false)).join("\n")
        const merged = A.mergeStatus(status, poll)
        T.ok(merged !== null, "a poll with the same agents is laid over the snapshot")
        const mail = merged.accounts.find(item => item.id === "akonadi_imap_resource_0")
        T.eq([mail.status, mail.statusMessage, mail.progress], [A.STATUS_RUNNING, "Fetching mail", 40], "the new status")
        T.eq([mail.typeName, mail.iconName, mail.kinds], ["IMAP E-Mail Server", "network-server", ["mail"]],
             "type, icon and kinds stay those of the whole snapshot")
        const calendar = merged.accounts.find(item => item.id === "akonadi_ical_resource_0")
        T.ok(!calendar.online, "online follows the poll")
        T.eq(merged.accounts[0].id, "akonadi_ical_resource_0", "and the order follows it too (offline before online)")
        T.eq([merged.tools, merged.agents, merged.server], [status.tools, status.agents, true], "the rest is kept")
        T.ok(status.accounts.find(item => item.id === "akonadi_imap_resource_0").status === A.STATUS_IDLE,
             "the snapshot itself is not changed")

        // A poll that leaves an account out (a call timed out) keeps it as it was.
        const partly = A.mergeStatus(status, ["@server running",
            "@agents akonadi_imap_resource_0 akonadi_ical_resource_0 akonadi_indexing_agent"]
            .concat(instance("akonadi_ical_resource_0", "", 0, true)).join("\n"))
        T.eq(partly.accounts.map(item => item.id).sort(), ["akonadi_ical_resource_0", "akonadi_imap_resource_0"],
             "no account goes missing")
        T.eq(partly.accounts.find(item => item.id === "akonadi_ical_resource_0").name, "iCal Calendar File",
             "an empty instance name falls back to the type's, as in the whole snapshot")

        // What asks for the whole snapshot again.
        T.eq(A.mergeStatus(status, ["@server running", "@agents akonadi_imap_resource_0 akonadi_ical_resource_0 "
            + "akonadi_indexing_agent akonadi_google_resource_0"].join("\n")), null, "an agent came")
        T.eq(A.mergeStatus(status, ["@server running", "@agents akonadi_imap_resource_0"].join("\n")), null, "an agent went")
        T.eq(A.mergeStatus(status, "@server stopped\n"), null, "the server stopped")
        T.eq(A.mergeStatus(status, "@server running\n"), null, "an answer without the agent list")
        T.eq(A.mergeStatus(status, ""), null, "no answer")
        T.eq(A.mergeStatus(A.parseStatus("@server running\n"), poll), null, "a snapshot that cannot be polled")
        T.finish("AccountsPollTest")
    }
}
