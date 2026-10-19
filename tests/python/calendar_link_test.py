#!/usr/bin/env python3
"""Unit test for scripts/calendar-link.py: calendars from a link as Akonadi
iCal resources, against a stand-in for the session bus. No D-Bus, no Akonadi:
the helper's bus is handed in (main's bus_factory). The links are invented
on reserved names."""

import contextlib
import importlib.util
import io
import json
import os
import pathlib
import sys

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("calendar_link", ROOT / "scripts" / "calendar-link.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

LINK = "https://outlook.example.com/owa/calendar/abc/def/reachcalendar.ics"
SECRET = "abc/def/reachcalendar.ics"


class FakeBus:
    """Akonadi as the helper sees it: an AgentManager, agents that answer on
    their own names, and a log of every call (none may carry the link but the
    one that sets it)."""

    def __init__(self, running=True, agents=None, appear_after=0, fail=None):
        self.running = running
        self.agents = dict(agents or {})
        self.calls = []
        self.next_id = 5
        self.appear_after = appear_after
        self.fail = fail or set()
        self.pending = {}

    def has_owner(self, name):
        if name == module.CONTROL:
            return self.running
        instance = name[len(module.AGENT_PREFIX):]
        if instance in self.pending:
            self.pending[instance] -= 1
            if self.pending[instance] > 0:
                return False
            del self.pending[instance]
        return instance in self.agents and self.agents[instance].get("up", True)

    def call(self, name, path, interface, method, signature="", args=()):
        self.calls.append((name, path, method, tuple(args)))
        if method in self.fail:
            raise module.Failure("dbus", "Akonadi refused it (org.example.Error.Failed).")
        if name == module.CONTROL:
            return self.manager(method, args)
        instance = name[len(module.AGENT_PREFIX):]
        agent = self.agents.get(instance)
        if agent is None or not agent.get("up", True):
            raise module.Failure("dbus", "Akonadi refused it (org.freedesktop.DBus.Error.ServiceUnknown).")
        if path == module.SETTINGS[0]:
            if method == "path":
                return agent.get("path", "")
            if method.startswith("set"):
                agent.setdefault("set", {})[method] = args[0]
                if method == "setPath":
                    agent["path"] = args[0]
                return []
            if method == "save":
                agent["saved"] = True
                return []
        if path == "/" and method == "reconfigure":
            agent["reconfigured"] = True
            return []
        raise AssertionError("unexpected call " + method)

    def manager(self, method, args):
        if method == "agentInstances":
            return list(self.agents)
        instance = args[0] if args else ""
        agent = self.agents.get(instance, {})
        if method == "agentInstanceType":
            return agent.get("type", "")
        if method == "agentInstanceName":
            return agent.get("name", "")
        if method == "agentInstanceStatus":
            return agent.get("status", 0)
        if method == "agentInstanceOnline":
            return agent.get("online", True)
        if method == "agentInstanceStatusMessage":
            return agent.get("message", "")
        if method == "createAgentInstance":
            new = "akonadi_ical_resource_%d" % self.next_id
            self.next_id += 1
            self.agents[new] = {"type": args[0], "path": ""}
            if self.appear_after:
                self.pending[new] = self.appear_after
            return new
        if method == "setAgentInstanceName":
            self.agents[args[0]]["name"] = args[1]
            return []
        if method == "agentInstanceSynchronize":
            self.agents[args[0]]["synced"] = True
            return []
        if method == "removeAgentInstance":
            self.agents.pop(args[0], None)
            return []
        raise AssertionError("unexpected manager call " + method)


def run(command, request=None, bus=None, env=None, clock=None):
    """main() with a request on stdin: (exit code, answer, stdout text)."""
    saved_env = dict(os.environ)
    os.environ.pop("BUCHHWIN_NESTED", None)
    os.environ.pop("XDG_CONFIG_HOME", None)
    os.environ.update(env or {})
    saved_stdin = sys.stdin
    sys.stdin = io.StringIO("" if request is None else json.dumps(request))
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            code = module.main([command], bus_factory=lambda: bus, sleep=lambda _seconds: None,
                               clock=clock or (lambda: 0.0))
    finally:
        sys.stdin = saved_stdin
        os.environ.clear()
        os.environ.update(saved_env)
    text = out.getvalue()
    return code, json.loads(text), text


def local_and_link():
    return {
        "akonadi_ical_resource_0": {"type": module.TYPE, "name": "Personal", "path": "/home/someone/.local/share/apps/korganizer/std.ics"},
        "akonadi_ical_resource_1": {"type": module.TYPE, "name": "Outlook", "path": LINK, "status": 2,
                                    "message": "Could not load file '" + LINK + "'."},
        "akonadi_maildir_resource_0": {"type": "akonadi_maildir_resource", "name": "Mail", "path": "https://mail.example.com/x"},
    }


# ---- links and names ---------------------------------------------------------
check(module.normalized("webcal://cal.example.test/a.ics") == "https://cal.example.test/a.ics", "webcal is https")
check(module.normalized("http://cal.example.test/a.ics") == "", "plain http is refused")
check(module.normalized("https://user:pw@cal.example.test/a.ics") == "", "a password in the link is refused")
check(module.normalized("https://cal.example.test/a b.ics") == "", "a space is refused")
check(module.normalized("") == "", "nothing is nothing")
check(module.host_of(LINK) == "outlook.example.com", "the host")
check(module.clean_name(" Work\nstuff ", LINK) == "Work stuff", "the name on one line")
check(module.clean_name("", LINK) == "outlook.example.com", "no name: the host")
check(SECRET not in module.redacted("Could not load file '" + LINK + "'.", LINK), "the link out of a message")
check(SECRET not in module.redacted("see https://outlook.example.com/" + SECRET, ""), "any https path out of a message")
check("outlook.example.com" in module.redacted("Could not load file '" + LINK + "'.", LINK), "the host stays")

# ---- list ----------------------------------------------------------------------
bus = FakeBus(agents=local_and_link())
code, answer, text = run("list", bus=bus)
check(code == 0 and answer["ok"], "list answers")
check([row["id"] for row in answer["calendars"]] == ["akonadi_ical_resource_1"],
      "only the iCal resource on a link: not the local file, not another resource type")
check(answer["calendars"][0]["host"] == "outlook.example.com", "with its host")
check(answer["calendars"][0]["status"] == 2, "and its status")
check(SECRET not in text, "the list never carries the link, not even in a status message")
check(not any(call[2].startswith("set") or call[2] in ("removeAgentInstance", "createAgentInstance") for call in bus.calls),
      "listing changes nothing")

code, answer, _text = run("list", bus=FakeBus(running=False))
check(code == 1 and answer["reason"] == "notRunning", "no Akonadi: an answer, nothing started")

# An agent that is down is skipped (its file cannot be asked).
agents = local_and_link()
agents["akonadi_ical_resource_1"]["up"] = False
code, answer, _text = run("list", bus=FakeBus(agents=agents))
check(answer["ok"] and answer["calendars"] == [], "an agent that does not answer is not listed")

# ---- add -------------------------------------------------------------------------
bus = FakeBus(agents=local_and_link(), appear_after=3)
code, answer, text = run("add", {"url": "webcal://outlook.example.com/owa/calendar/abc/def/reachcalendar.ics", "name": "Work"}, bus=bus)
check(code == 0 and answer["ok"], "add works")
check(answer["id"] == "akonadi_ical_resource_5", "and names the new calendar")
made = bus.agents["akonadi_ical_resource_5"]
check(made["set"] == {"setPath": LINK, "setDisplayName": "Work", "setReadOnly": True, "setMonitorFile": False,
                      "setPeriodicUpdate": True, "setUpdatePeriod": 15}, "read-only, every 15 minutes, on the https link")
check(made.get("saved") and made.get("reconfigured") and made.get("synced"), "saved, read in and fetched")
check(made["name"] == "Work", "with the name as the instance's name too")
check(SECRET not in text, "the answer does not carry the link")
link_calls = [call for call in bus.calls if any(SECRET in str(arg) for arg in call[3])]
check(len(link_calls) == 1 and link_calls[0][2] == "setPath", "the link goes to setPath and nowhere else")
check([row["id"] for row in answer["calendars"]] == ["akonadi_ical_resource_1", "akonadi_ical_resource_5"],
      "the answer lists the calendars after it")

bus = FakeBus(agents={})
run("add", {"url": LINK, "name": "", "refreshMinutes": 2}, bus=bus)
check(bus.agents["akonadi_ical_resource_5"]["set"]["setUpdatePeriod"] == 15, "a period out of range is the default")
check(bus.agents["akonadi_ical_resource_5"]["set"]["setDisplayName"] == "outlook.example.com", "no name: the host")

bus = FakeBus(agents={})
code, answer, _text = run("add", {"url": "http://cal.example.test/a.ics"}, bus=bus)
check(code == 1 and not answer["ok"] and bus.agents == {}, "a refused link makes nothing")

# A failing step takes the half-made resource away again.
bus = FakeBus(agents={}, fail={"setReadOnly"})
code, answer, text = run("add", {"url": LINK, "name": "Work"}, bus=bus)
check(code == 1 and answer["reason"] == "dbus", "a refused step is an answer")
check("akonadi_ical_resource_5" not in bus.agents, "and the empty calendar is gone")
check(SECRET not in text, "the error carries no link")

# An agent that never comes up.
bus = FakeBus(agents={}, appear_after=10 ** 9)
ticks = iter(range(0, 10 ** 6))
code, answer, _text = run("add", {"url": LINK}, bus=bus, clock=lambda: float(next(ticks)))
check(code == 1 and answer["reason"] == "timeout", "a calendar that never starts times out")
check("akonadi_ical_resource_5" not in bus.agents, "and is removed")

# ---- remove and sync ----------------------------------------------------------------
bus = FakeBus(agents=local_and_link())
code, answer, _text = run("remove", {"id": "akonadi_ical_resource_1"}, bus=bus)
check(code == 0 and "akonadi_ical_resource_1" not in bus.agents, "a link calendar is removed")
for victim in ("akonadi_ical_resource_0", "akonadi_maildir_resource_0", "akonadi_ical_resource_9", "../x", ""):
    bus = FakeBus(agents=local_and_link())
    code, answer, _text = run("remove", {"id": victim}, bus=bus)
    check(code == 1 and answer["reason"] == "notLink" and set(bus.agents) == set(local_and_link()),
          "never anything but a link calendar: " + repr(victim))
bus = FakeBus(agents=local_and_link())
code, answer, _text = run("sync", {"id": "akonadi_ical_resource_1"}, bus=bus)
check(code == 0 and bus.agents["akonadi_ical_resource_1"].get("synced"), "a link calendar fetched now")
code, answer, _text = run("sync", {"id": "akonadi_ical_resource_0"}, bus=FakeBus(agents=local_and_link()))
check(code == 1 and answer["reason"] == "notLink", "not the local one")

# ---- where it refuses ------------------------------------------------------------------
bus = FakeBus(agents=local_and_link())
code, answer, _text = run("list", bus=bus, env={"BUCHHWIN_NESTED": "1"})
check(code == 1 and answer["reason"] == "sandbox" and bus.calls == [], "a nested session reaches nothing")
code, answer, _text = run("add", {"url": LINK}, bus=FakeBus(), env={"XDG_CONFIG_HOME": "/tmp/elsewhere"})
check(answer["reason"] == "sandbox", "nor does a sandboxed configuration")
code, answer, _text = run("nonsense", bus=FakeBus())
check(code == 1 and "usage" in answer["error"], "an unknown command")
# As run() does: the caller's own nested or sandboxed environment must not
# turn this into a "sandbox" answer.
saved = sys.stdin
saved_env = dict(os.environ)
os.environ.pop("BUCHHWIN_NESTED", None)
os.environ.pop("XDG_CONFIG_HOME", None)
sys.stdin = io.StringIO("not json")
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out):
        code = module.main(["add"], bus_factory=FakeBus, sleep=lambda _s: None)
finally:
    sys.stdin = saved
    os.environ.clear()
    os.environ.update(saved_env)
check(code == 1 and "could not be read" in json.loads(out.getvalue()).get("error", ""), "a request that is no JSON")

if failures:
    for failure in failures:
        print("FAIL calendar_link_test: " + failure)
    sys.exit(1)
print("calendar_link_test: all passed")
