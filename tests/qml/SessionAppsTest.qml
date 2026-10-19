import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/sessionapps/PlacementLogic.js" as P
import "../../services/sessionapps/ReopenLogic.js" as R

// Apps in their places (services/sessionapps/): the placements and work apps
// of apps.json, the window rules they become in both dialects and how they
// are switched, and the last session's apps - what is kept, what a reopen
// starts and where each window goes. The monitors are invented.
ShellRoot {
    Component.onCompleted: {
        const desk = { name: "DP-10", description: "Example Display 27 0001", model: "Display 27" }
        const portrait = { name: "DP-13", description: "Example Display 24 0002", model: "" }
        const laptop = { name: "eDP-1", description: "", model: "" }
        const monitors = [laptop, desk, portrait]
        const offsets = { "DP-10": 0, "DP-13": 10, "eDP-1": 20 }

        // ---- apps.json --------------------------------------------------------------
        const store = P.parseStore(JSON.stringify({
            version: 1, extra: "kept out",
            placement: [
                { app: "org.kde.dolphin", screen: desk.description, screenName: "DP-10", workspace: 3, float: false, title: "x" },
                { app: "org.kde.dolphin", screen: "", workspace: 1 },
                { app: "outlook", screen: "", screenName: "DP-13", workspace: 11 },
                { app: "floaty", float: true, workspace: 4 },
                { app: "", screenName: "DP-10" }, { app: "bad\nid" }, "nonsense", null
            ],
            workApps: ["a", "a", "b", "", 3, "c\u0001"]
        }), 10)
        T.eq(store.placement.length, 3, "one placement per app, broken ones left out")
        T.eq(store.placement[0], { app: "org.kde.dolphin", screen: desk.description, screenName: "DP-10", workspace: 3, float: false },
             "only the fields of a placement")
        T.eq(store.placement[1].workspace, 0, "a workspace beyond the block is the shown one")
        T.eq(store.placement[2], { app: "floaty", screen: "", screenName: "", workspace: 0, float: true },
             "without a screen there is no workspace to name, only floating")
        T.eq(store.workApps, ["a", "b"], "work apps once each, valid ids only")
        T.eq(P.parseStore("not json"), P.emptyStore(), "an unreadable file is an empty one")
        T.eq(P.parseStore(P.serializeStore(store), 10), store, "written and read back the same")
        T.eq(P.serializeStore(store).slice(-1), "\n", "ends with a newline")

        let next = P.withRule(store, { app: "org.kde.dolphin", screenName: "eDP-1", workspace: 2 }, 10)
        T.eq([next.placement.length, next.placement[0].screenName, next.placement[0].workspace], [3, "eDP-1", 2], "replaced in place")
        next = P.withRule(next, { app: "new.app", screenName: "DP-13", workspace: 1, float: true }, 10)
        T.eq(next.placement[3], { app: "new.app", screen: "", screenName: "DP-13", workspace: 1, float: true }, "added at the end")
        T.ok(P.withRule(next, { app: "" }, 10) === next, "a rule that is none changes nothing")
        T.eq(P.withoutRule(next, "outlook").placement.map(rule => rule.app), ["org.kde.dolphin", "floaty", "new.app"], "removed")
        let full = P.emptyStore()
        for (let index = 0; index < P.MAX_RULES; ++index) full = P.withRule(full, { app: "app" + index, float: true }, 10)
        T.ok(P.withRule(full, { app: "one.more", float: true }, 10) === full, "at most " + P.MAX_RULES + " placements")
        T.eq(P.withRule(full, { app: "app3", screenName: "DP-10" }, 10).placement[3].screenName, "DP-10", "a full list still takes a change")
        T.eq(P.withWorkApp(P.withWorkApp(store, "c"), "a").workApps, ["a", "b", "c"], "a work app added once")
        T.eq(P.withoutWorkApp(store, "a").workApps, ["b"], "and removed")
        T.eq(P.ruleFor(store, "outlook").screenName, "DP-13", "looked up by app")
        T.eq(P.ruleFor(store, "nope"), null, "none for another")

        // ---- screens and targets ------------------------------------------------------
        T.eq(P.monitorFor({ screen: desk.description, screenName: "DP-3" }, monitors).name, "DP-10",
             "the screen by its description, on whatever connector it is now")
        T.eq(P.monitorFor({ screen: "", screenName: "eDP-1" }, monitors).name, "eDP-1", "else by its connector")
        T.eq(P.monitorFor({ screen: "Example Display 99", screenName: "DP-10" }, monitors).name, "DP-10",
             "a description that is not here falls back to the connector")
        T.eq(P.monitorFor({ screen: "Example Display 99", screenName: "" }, monitors), null, "not connected")
        T.eq([P.screenLabel(desk), P.screenLabel(portrait), P.screenLabel(laptop), P.screenLabel(null)],
             ["Display 27 (DP-10)", "Example Display 24 0002 (DP-13)", "eDP-1", ""], "screens in words")

        T.eq(P.ruleTarget(store.placement[0], monitors, offsets), { monitor: "DP-10", workspace: 3, float: false },
             "the first block's third")
        T.eq(P.ruleTarget(P.sanitizeRule({ app: "o", screenName: "DP-13", workspace: 3 }, 10), monitors, offsets),
             { monitor: "DP-13", workspace: 13, float: false }, "the second screen's third is 13: the block's own id")
        T.eq(P.ruleTarget(P.sanitizeRule({ app: "o", screenName: "DP-13", workspace: 3 }, 10), monitors, {}),
             { monitor: "DP-13", workspace: 3, float: false }, "without workspaces per monitor the number itself")
        T.eq(P.ruleTarget(store.placement[1], monitors, offsets), { monitor: "DP-13", workspace: 0, float: false }, "the shown workspace of a screen")
        T.eq(P.ruleTarget(P.sanitizeRule({ app: "o", screenName: "DP-99", workspace: 2 }, 10), monitors, offsets), null,
             "a screen that is not here: no rule")
        T.eq(P.ruleTarget(P.sanitizeRule({ app: "o", screenName: "DP-13" }, 10), monitors, offsets),
             { monitor: "DP-13", workspace: 0, float: false }, "the screen alone")
        T.eq(P.ruleTarget(store.placement[2], monitors, offsets), { monitor: "", workspace: 0, float: true }, "floating anywhere")
        T.eq(P.ruleTarget(P.sanitizeRule({ app: "o" }, 10), monitors, offsets), null, "nothing to do, no rule")

        // ---- matching windows ---------------------------------------------------------
        T.eq(P.literal("org.kde.dolphin"), "org[.]kde[.]dolphin", "dots in a class of their own")
        T.eq(P.literal("a$b(c)*+?|{}[x"), "a[$]b[(]c[)][*][+][?][|][{][}][[]x", "every special")
        T.eq([P.literal("a,b"), P.literal("a;b"), P.literal("a#b"), P.literal("a\\b"), P.literal("a]b"), P.literal("a^b"), P.literal("")],
             [null, null, null, null, null, null, null], "what a rule cannot carry is refused")
        T.eq(P.classNames({ id: "org.kde.dolphin", startupClass: "" }), ["org.kde.dolphin", "dolphin"], "reverse DNS and its last part")
        T.eq(P.classNames({ id: "code", startupClass: "Code" }), ["code"], "StartupWMClass, the same name once")
        T.eq(P.classNames({ id: "brave-abc-Default", startupClass: "crx_abc" }), ["brave-abc-default", "crx_abc"],
             "a web app: its Wayland class and its XWayland one")
        T.eq(P.matchFor({ id: "org.kde.dolphin" }), { "class": "(?i)^(org[.]kde[.]dolphin|dolphin)$" }, "one pattern for all, any case")
        T.eq(P.matchFor({ id: "Citrix_subscribed_XenApp 7.x.RDS-Name $S101-255", name: "RDS-Name", startupClass: "RDS-Name",
                          categories: ["Network", "Citrix-subscribed"] }),
             { "class": "(?i)^(wfica)$", title: "(?i)^(RDS-Name)([^0-9a-z_.-].*)?$" },
             "a Citrix desktop: the session class and its name at the title's start")
        T.eq(P.matchFor({ id: "a,b" }), null, "nothing to match")
        T.eq(P.matchFor(null), null, "no entry")

        // ---- the rules ------------------------------------------------------------------
        const match = P.matchFor({ id: "org.kde.dolphin" })
        const target = { monitor: "DP-13", workspace: 13, float: true }
        const name = P.ruleName(match, target)
        T.ok(/^buchhwin-place-[0-9a-z]+$/.test(name), "a short stable name")
        T.eq(P.ruleName(match, target), name, "the same placement, the same name")
        T.ok(P.ruleName(match, { monitor: "DP-13", workspace: 14, float: true }) !== name, "another workspace, another rule")
        const command = P.ruleCommand(name, match, target)
        T.eq(command.legacy, "keyword windowrule monitor DP-13 silent, workspace 13 silent, float on, match:class (?i)^(org[.]kde[.]dolphin|dolphin)$",
             "conf: an anonymous windowrule, naming the screen")
        T.eq(command.lua, "buchhwin_places = buchhwin_places or {}\nif buchhwin_places[\"" + name + "\"] then "
             + "hl.window_rule({ name = \"" + name + "\", enabled = true }) else buchhwin_places[\"" + name + "\"] = true; "
             + "hl.window_rule({ name = \"" + name + "\", match = { class = \"(?i)^(org[.]kde[.]dolphin|dolphin)$\" }, "
             + "monitor = \"DP-13 silent\", workspace = \"13 silent\", float = true }) end",
             "Lua: a named rule, declared once per config load and switched on after that")
        T.eq(P.ruleCommand("n", match, { monitor: "DP-10", workspace: 0, float: false }).legacy,
             "keyword windowrule monitor DP-10, match:class (?i)^(org[.]kde[.]dolphin|dolphin)$", "the screen alone")
        const citrix = P.ruleCommand("n", { "class": "(?i)^(wfica)$", title: "(?i)^(LAB)([^0-9a-z_.-].*)?$" },
                                     { monitor: "DP-10", workspace: 2, float: false })
        T.eq(citrix.legacy, "keyword windowrule monitor DP-10 silent, workspace 2 silent, match:class (?i)^(wfica)$, match:title (?i)^(LAB)([^0-9a-z_.-].*)?$",
             "a title beside the class")
        T.ok(citrix.lua.indexOf("match = { class = \"(?i)^(wfica)$\", title = ") > 0, "in Lua too")
        T.eq(P.ruleSwitch("n", false).lua, "hl.window_rule({ name = \"n\", enabled = false })", "off by its name")
        T.eq(P.ruleSwitch("n", true).legacy, "", "the conf dialect cannot")

        const entryFor = app => app === "org.kde.dolphin" ? { id: app, startupClass: "" } : null
        const wanted = P.wantedRules(store, monitors, offsets, entryFor)
        T.eq(wanted.map(item => item.app), ["org.kde.dolphin", "outlook", "floaty"], "a rule per placement whose screen is here")
        T.eq(P.wantedRules(P.withRule(store, { app: "elsewhere", screenName: "DP-99" }, 10), monitors, offsets, entryFor).length, 3,
             "none for a screen that is not connected")
        T.ok(wanted[2].command.legacy.indexOf("match:class (?i)^(floaty)$") > 0, "an app not installed: its id is its class")

        let plan = P.rulePlan({}, wanted, true)
        T.eq(plan.commands, [P.ruleSweep(wanted.map(item => item.name))].concat(wanted.map(item => item.command)),
             "after a start: what an earlier run left on is swept first, then the rules declared")
        T.ok(plan.commands[0].lua.indexOf("for name in pairs(buchhwin_places or {}) do if not keep[name] then "
             + "hl.window_rule({ name = name, enabled = false }) end end") > 0
             && plan.commands[0].lua.indexOf("[\"" + wanted[2].name + "\"] = true") > 0, "every name off but the wanted ones")
        T.eq(Object.keys(plan.known).length, 3, "and known")
        T.eq(P.rulePlan(plan.known, wanted, true).commands, [], "nothing again while they hold")
        const fewer = P.rulePlan(plan.known, wanted.slice(0, 2), true)
        T.eq(fewer.commands, [P.ruleSwitch(wanted[2].name, false)], "one no longer wanted: off by its name")
        T.eq(fewer.known[wanted[2].name].on, false, "known as off")
        T.eq(P.rulePlan(fewer.known, wanted, true).commands, [P.ruleSwitch(wanted[2].name, true)], "wanted again: on, not declared twice")
        T.eq(P.rulePlan({}, [], true).commands, [P.ruleSweep([])], "no place has its screen here: an earlier run's rules all off")
        T.eq(P.rulePlan({}, wanted.concat(wanted), true).commands.length, 4, "a name once")

        const confPlan = P.rulePlan({}, wanted, false)
        T.eq([confPlan.commands, confPlan.stale], [wanted.map(item => item.command), 0], "conf: declared, nothing to sweep")
        const confFewer = P.rulePlan(confPlan.known, wanted.slice(1), false)
        T.eq(confFewer.commands.map(command => command.legacy),
             ["keyword windowrule monitor unset, workspace unset, match:class (?i)^(org[.]kde[.]dolphin|dolphin)$"],
             "conf: taken back by a later rule that unsets its screen and workspace")
        T.eq([confFewer.known[wanted[0].name].on, confFewer.stale], [false, 0], "known as off, nothing held")
        T.eq(P.rulePlan(confFewer.known, wanted, false).commands, [wanted[0].command], "wanted again: declared again, after its release")
        const conf = P.rulePlan(confPlan.known, wanted.slice(0, 2), false)
        T.eq([conf.commands, conf.stale], [[], 1], "floating anywhere has nothing to unset: it floats until a reload, and says so")
        T.eq(P.rulePlan(conf.known, wanted, false).commands, [wanted[2].command], "and wanted again it is declared again")
        const moved = P.wantedRules(P.withRule(store, { app: "org.kde.dolphin", screen: desk.description, screenName: "DP-10", float: true }, 10),
                                    monitors, offsets, entryFor)
        T.eq(P.rulePlan(confPlan.known, moved, false).commands, [P.ruleRelease(wanted[0].match, wanted[0].target), moved[0].command],
             "a place changed: the old rule released first, so the new one comes later and wins")
        T.eq(P.rulePlan(plan.known, moved, true).commands, [P.ruleSwitch(wanted[0].name, false), moved[0].command], "in Lua too")
        T.eq(P.ruleRelease({ "class": "(?i)^(wfica)$", title: "(?i)^(LAB)([^0-9a-z_.-].*)?$" }, { monitor: "DP-10", workspace: 0, float: false }).legacy,
             "keyword windowrule monitor unset, match:class (?i)^(wfica)$, match:title (?i)^(LAB)([^0-9a-z_.-].*)?$", "only what the rule set, title and all")
        T.eq(P.ruleRelease(match, { monitor: "", workspace: 0, float: true }), null, "nothing to unset, no release")

        // ---- words and the dock ------------------------------------------------------------
        T.eq(P.describeRule(store.placement[0], "Display 27 (DP-10)"), "Workspace 3 on Display 27 (DP-10)", "a workspace on a screen")
        T.eq(P.describeRule(P.sanitizeRule({ app: "a", screenName: "DP-13", float: true }, 10), "DP-13"),
             "The shown workspace on DP-13 · floating", "the shown one, floating")
        T.eq(P.describeRule(P.sanitizeRule({ app: "a", screen: "Example Display 99", workspace: 2 }, 10), ""),
             "Workspace 2 on Example Display 99, not connected", "a screen not connected")
        T.eq([P.describeRule(store.placement[2], ""), P.describeRule(P.sanitizeRule({ app: "a" }, 10), "")],
             ["Floating on any screen", "Any screen"], "no screen")
        const here = P.hereRule("org.kde.dolphin", desk, 3, 10)
        T.eq(here, { app: "org.kde.dolphin", screen: desk.description, screenName: "DP-10", workspace: 3, float: false },
             "always here: this screen, its shown workspace")
        T.eq(P.hereRule("a", desk, 14, 10).workspace, 0, "beyond the block: the shown one")
        T.eq([P.isHere(store.placement[0], here), P.isHere(store.placement[2], here), P.isHere(null, here)],
             [true, false, false], "here already, or not")
        T.eq(P.hereRule("", desk, 1, 10), null, "no app, no row")

        // ---- keeping a session --------------------------------------------------------------
        T.eq([R.normalizeAddress("0x55AA01"), R.normalizeAddress("55aa01"), R.normalizeAddress("0xzz"), R.normalizeAddress("")],
             ["55aa01", "55aa01", "", ""], "addresses without 0x")
        T.eq(R.workspacePlace(13, "DP-13", offsets, true, 10), { workspace: 3, local: true }, "the third of DP-13's block")
        T.eq(R.workspacePlace(35, "DP-13", offsets, true, 10), { workspace: 35, local: false }, "a stray beyond the block keeps its id")
        T.eq(R.workspacePlace(13, "DP-13", offsets, false, 10), { workspace: 13, local: false }, "global numbers")
        const windows = [
            { address: "55aa01", cls: "org.kde.dolphin", app: "org.kde.dolphin", workspace: 13, monitor: "DP-13", title: "Secret" },
            { address: "0x55aa02", cls: "Probe", app: "", workspace: 2, monitor: "DP-10" },
            { address: "55aa03", cls: "xwaylandvideobridge", app: "", workspace: 1, monitor: "DP-10" },
            { address: "55aa04", cls: "alacritty", app: "Alacritty", workspace: -98, monitor: "DP-10" },
            { address: "", cls: "a", workspace: 1 }, { address: "55aa05", cls: "", workspace: 1 }, null
        ]
        const kept = R.snapshotWindows(windows, { monitors: monitors, offsets: offsets, perMonitor: true, block: 10,
                                                   hidden: cls => cls === "xwaylandvideobridge" })
        T.eq(kept, [
            { address: "0x55aa01", app: "org.kde.dolphin", cls: "org.kde.dolphin", monitor: portrait.description, monitorName: "DP-13", workspace: 3, local: true },
            { address: "0x55aa02", app: "", cls: "probe", monitor: desk.description, monitorName: "DP-10", workspace: 2, local: true }
        ], "real workspaces only, no helpers, no title - the screen by its description and the place in its block")

        const state = R.parseState(JSON.stringify({ version: 1, savedAt: "2026-10-19T18:00:00Z", offered: false, entries: [
            { app: "org.kde.dolphin", cls: "org.kde.dolphin", monitor: portrait.description, monitorName: "DP-13", workspace: 3, local: true,
              floating: true, x: 100, y: 50, width: 800, height: 600, title: "Secret" },
            { app: "org.kde.dolphin", cls: "org.kde.dolphin", monitorName: "DP-10", workspace: 2, local: true, floating: false },
            { app: "", cls: "probe", monitorName: "gone-1", workspace: 4, local: true },
            { app: "brave-browser", cls: "brave-browser", monitorName: "DP-10", workspace: 1, local: true },
            { app: "brave-outlook-Default", cls: "brave-outlook-default", monitor: portrait.description, workspace: 1, local: true },
            { app: "x", cls: "x", workspace: 0 }, { cls: "", workspace: 1 }, { app: "y", cls: "y", workspace: 1, floating: true, x: 1 }
        ] }))
        T.eq(state.entries.length, 6, "broken entries left out")
        T.ok(state.entries.every(entry => entry.title === undefined), "a title in the file is never read")
        T.eq(state.entries[5].floating, false, "floating without a whole geometry is tiled")
        T.eq([state.savedAt, state.offered], ["2026-10-19T18:00:00Z", false], "when, and not offered yet")
        T.eq(R.parseState("[]"), R.emptyState(), "not a state")
        T.eq(R.appCount(state.entries), 5, "five apps")
        T.eq(R.offerText(1).body.indexOf("1 app was open"), 0, "one app")
        T.eq(R.offerText(5).title, "Reopen your apps?", "the offer asks")
        T.eq([R.wantsOffer(state, true), R.wantsOffer(state, false), R.wantsOffer(Object.assign({}, state, { offered: true }), true),
              R.wantsOffer(R.emptyState(), true)], [true, false, false, false], "offered once, only when on and with something to offer")

        // ---- starting -----------------------------------------------------------------------
        const groups = R.groups(state.entries)
        T.eq(groups.map(group => group.key), ["org.kde.dolphin", "class:probe", "brave-browser", "brave-outlook-Default", "y"],
             "by app, in the order first seen; an unknown app by its class")
        T.eq(groups[0].places.length, 2, "two windows of the file manager")
        T.eq(R.restoreKind({ id: "brave-browser", command: ["/opt/brave-bin/brave"] }), { family: "launch-brave.sh", restores: true, placeOnly: false },
             "the browser restores its own windows")
        T.eq(R.restoreKind({ id: "brave-outlook-Default", command: ["/opt/brave-bin/brave", "--app-id=x"] }).family, "launch-brave.sh",
             "a web app is of the browser's family")
        T.eq(R.restoreKind({ id: "code", command: ["/usr/bin/code"] }), { family: "code", restores: true, placeOnly: false }, "VS Code too")
        T.eq(R.restoreKind({ id: "Citrix_subscribed_LAB", categories: ["Citrix-subscribed"], command: ["x"] }),
             { family: "citrix", restores: true, placeOnly: true }, "a Citrix desktop is only put back: Citrix reconnects it")
        T.eq(R.restoreKind({ id: "org.kde.dolphin", command: ["dolphin"] }), { family: "org.kde.dolphin", restores: false, placeOnly: false }, "one window per start")

        const info = app => app === "org.kde.dolphin" ? { family: app, restores: false }
            : app.indexOf("brave") === 0 ? { family: "launch-brave.sh", restores: true } : null
        let queue = R.launchQueue(groups, info, {})
        T.eq(queue.map(item => [item.app, item.count]), [["org.kde.dolphin", 2], ["brave-browser", 1], ["brave-outlook-Default", 1]],
             "one start per window, a browser and each web app once, nothing for what is not installed")
        T.eq(R.launchQueue(R.groups([{ app: "c-lab", cls: "wfica", workspace: 2 }]), () => ({ family: "citrix", restores: true, placeOnly: true }), {}),
             [], "never a start for a Citrix desktop")
        T.eq(R.launchQueue(groups, info, { "org.kde.dolphin": 1, "brave-browser": 2 }).map(item => [item.app, item.count]),
             [["org.kde.dolphin", 1], ["brave-outlook-Default", 1]], "what is open already counts")
        const many = R.groups(Array.from({ length: 30 }, (unused, index) => ({ app: "app" + index, cls: "c" + index, workspace: 1 })))
        T.eq(R.launchQueue(many, () => ({ family: "f", restores: false }), {}).length, R.MAX_TOTAL_LAUNCHES, "a bound on the starts")
        T.eq(R.launchQueue([{ key: "t", app: "t", cls: "t", places: [1, 2, 3, 4, 5, 6] }], () => ({ family: "t", restores: false }), {})[0].count,
             R.MAX_LAUNCHES, "and on one app's windows")

        T.eq(R.nextLaunch(queue, {}, {}, 1000), 0, "the first")
        queue[0].launched = 2
        T.eq(R.nextLaunch(queue, {}, {}, 1000), 1, "then the browser")
        queue[1].launched = 1
        const wait = { "launch-brave.sh": 1000 + R.FAMILY_WAIT_MS }
        T.eq(R.nextLaunch(queue, {}, wait, 2000), -1, "its web app waits while the browser starts")
        T.ok(R.launchesLeft(queue, {}), "but is still to come")
        T.eq(R.nextLaunch(queue, { "brave-outlook-Default": 1 }, {}, 2000), -1, "the browser brought it back: not started")
        T.ok(!R.launchesLeft(queue, { "brave-outlook-Default": 1 }), "and nothing is left")
        T.eq(R.nextLaunch(queue, {}, wait, 1000 + R.FAMILY_WAIT_MS + 1), 2, "the wait ends, the web app starts")
        const arrived = R.familyArrived(wait, "launch-brave.sh", 2000)
        T.eq(arrived["launch-brave.sh"], 2000 + R.FAMILY_SETTLE_MS, "the browser's first window: the family goes on a moment later")
        T.eq(R.nextLaunch(queue, {}, arrived, 2000 + R.FAMILY_SETTLE_MS - 1), -1, "the windows it brings back still come first")
        T.eq(R.nextLaunch(queue, {}, arrived, 2000 + R.FAMILY_SETTLE_MS + 1), 2, "then the web app, if none of them was it")
        T.eq(R.familyArrived(arrived, "launch-brave.sh", 4000)["launch-brave.sh"], 2000 + R.FAMILY_SETTLE_MS, "its next windows hold it no longer")
        T.eq(R.familyArrived({ "launch-brave.sh": 2500 }, "launch-brave.sh", 2000)["launch-brave.sh"], 2500, "nor a wait that ends sooner")
        T.ok(R.familyArrived(wait, "code", 2000) === wait, "a family that does not wait: nothing changes")

        // ---- placing -------------------------------------------------------------------------
        let pending = R.pendingFrom(groups)
        T.eq(R.pendingCount(pending), 6, "every window a place")
        let taken = R.takePlace(pending, ["org.kde.dolphin", "class:org.kde.dolphin"])
        T.eq([taken.key, taken.place.workspace, taken.place.floating], ["org.kde.dolphin", 3, true], "the first window takes the first place")
        taken = R.takePlace(taken.pending, ["org.kde.dolphin"])
        T.eq(taken.place.workspace, 2, "the next one the next")
        T.eq(taken.pending["org.kde.dolphin"], undefined, "all taken")
        T.eq(R.takePlace(taken.pending, ["org.kde.dolphin"]), null, "a third window stays where it opens")
        T.eq(R.takePlace(pending, ["probe-app", "class:probe"]).key, "class:probe", "a window of no known app by its class")
        T.ok(pending["org.kde.dolphin"].length === 2, "taking never changes what it took from")

        const screens = { "DP-10": { x: 0, y: 0, width: 2304, height: 1296 }, "DP-13": { x: 2304, y: 0, width: 1296, height: 2304 },
                          "eDP-1": { x: 3600, y: 0, width: 1920, height: 1200 } }
        T.eq(R.targetOf(state.entries[0], monitors, offsets, true, "DP-10", screens),
             { monitor: "DP-13", workspace: 13, geometry: { x: 2404, y: 50, width: 800, height: 600 } },
             "back on the portrait screen's third, at its spot")
        T.eq(R.targetOf(state.entries[2], monitors, offsets, true, "eDP-1", screens), { monitor: "eDP-1", workspace: 24, geometry: null },
             "a screen that is not here: the same place on the focused one")
        T.eq(R.targetOf(state.entries[0], monitors, offsets, false, "DP-10", screens).workspace, 3, "global numbers")
        T.eq(R.targetOf(Object.assign({}, state.entries[0], { x: 2000, width: 3000 }), monitors, offsets, true, "DP-10", screens).geometry,
             { x: 2304, y: 50, width: 1296, height: 600 }, "kept on its screen")
        T.eq(R.targetOf(state.entries[0], [], {}, true, "", {}), { monitor: "", workspace: 3, geometry: null }, "no screens known")

        const steps = R.placeCommands("55aa01", { monitor: "DP-13", workspace: 13, geometry: { x: 2404, y: 50, width: 800, height: 600 } })
        T.eq(steps.map(step => step.legacy), ["movetoworkspacesilent 13,address:0x55aa01", "setfloating address:0x55aa01",
                                             "movewindowpixel exact 2404 50,address:0x55aa01", "resizewindowpixel exact 800 600,address:0x55aa01"],
             "conf: to its workspace without following, floating, its spot, its size")
        T.eq(steps.map(step => step.lua), [
            "hl.dsp.window.move({ workspace = 13, window = \"address:0x55aa01\", follow = false })",
            "hl.dsp.window.float({ action = \"enable\", window = \"address:0x55aa01\" })",
            "hl.dsp.window.move({ x = 2404, y = 50, relative = false, window = \"address:0x55aa01\" })",
            "hl.dsp.window.resize({ x = 800, y = 600, relative = false, window = \"address:0x55aa01\" })"], "Lua the same")
        T.eq(R.placeCommands("55aa01", { monitor: "DP-10", workspace: 2, geometry: null }).length, 1, "a tiled one only moves")
        T.eq([R.placeCommands("zz", { workspace: 2 }), R.placeCommands("55aa01", { workspace: 0 }), R.placeCommands("55aa01", null)],
             [[], [], []], "nothing for a bad address or no workspace")

        T.eq(R.parseOpenWindow("55aa09,13,org.kde.dolphin,Docs, notes, 2026"),
             { address: "55aa09", cls: "org.kde.dolphin", title: "Docs, notes, 2026" }, "socket2's openwindow, commas in the title")
        T.eq([R.parseOpenWindow("55aa09,13"), R.parseOpenWindow("zz,1,a,b")], [null, null], "broken events")
        const citrixEntries = [{ id: "c-lab", name: "LAB", startupClass: "LAB" }, { id: "c-office", name: "RDS-Office", startupClass: "RDS-Office" },
                               { id: "c-rds", name: "RDS", startupClass: "RDS" }]
        T.eq([R.citrixEntryFor("LAB - Desktop Viewer", citrixEntries), R.citrixEntryFor("LABRADOR", citrixEntries),
              R.citrixEntryFor("RDS-Office (SSL/TLS Secured)", citrixEntries), R.citrixEntryFor("rds desktop", citrixEntries),
              R.citrixEntryFor("", citrixEntries)], ["c-lab", "", "c-office", "c-rds", ""], "a session by its desktop's name, as a whole word")

        T.finish("SessionAppsTest")
    }
}
