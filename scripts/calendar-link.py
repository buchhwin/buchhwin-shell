#!/usr/bin/env python3
"""Calendars from a link for buchhwin-shell: Akonadi iCal resources on a URL.

Settings > Calendar "Add calendar from a link" puts a published calendar -
Outlook's "Publish a calendar" ICS link, a Google calendar's secret address,
any .ics on the web - into KDE's calendars: a new instance of Akonadi's own
iCal resource with the link as its file, read-only, fetched again every 15
minutes. Akonadi does the fetching (KIO, with the system's certificates and
proxy) and keeps the copy; the shell shows the events as it shows every KDE
calendar. This is what Merkuro's "Add calendar > iCal calendar file" does,
without its dialog.

  calendar-link.py list            the link calendars: id, name, host, status
  calendar-link.py add     < json  {"url", "name"[, "refreshMinutes"]} -> a new one
  calendar-link.py remove  < json  {"id"} -> that calendar gone (a link one only)
  calendar-link.py sync    < json  {"id"} -> fetch it now

Every command prints exactly one JSON object on stdout. A published link can
be read by anyone who has it, so it is read from stdin and never printed,
logged or put on a command line; answers name its host only. Akonadi keeps it
in the resource's configuration, as it keeps every calendar's address.

Nothing here starts Akonadi or an agent: every call goes out without
auto-start (testing.md pitfall 27), and a server that is not running is an
answer ("notRunning"). It talks to the user's own session only and refuses in
a nested test session, like calendar-helper.py.

The resource's D-Bus interface (kdepim-runtime, org.kde.Akonadi.ICal.Settings
on /Settings): setPath, setDisplayName, setReadOnly, setMonitorFile,
setPeriodicUpdate, setUpdatePeriod (minutes), save; the agent's
org.freedesktop.Akonadi.Agent.Control.reconfigure reads them in.
"""

import json
import os
import pathlib
import re
import sys
import time

CONTROL = "org.freedesktop.Akonadi.Control"
MANAGER = ("/AgentManager", "org.freedesktop.Akonadi.AgentManager")
AGENT_PREFIX = "org.freedesktop.Akonadi.Agent."
SETTINGS = ("/Settings", "org.kde.Akonadi.ICal.Settings")
AGENT_CONTROL = ("/", "org.freedesktop.Akonadi.Agent.Control")
TYPE = "akonadi_ical_resource"
ID = re.compile(r"^akonadi_ical_resource_\d+$")
REMOTE = re.compile(r"^https://", re.IGNORECASE)
HOST = re.compile(r"^https://(?:[^/?#@]*@)?([^/?#:]+)", re.IGNORECASE)
DEFAULT_REFRESH = 15
# A new agent registers its bus name, then its /Settings object; both within
# a second or two here. Akonadi's own calls answer in milliseconds.
APPEAR_SECONDS = 20.0
CALL_SECONDS = 10.0


def result(**values):
    print(json.dumps(values, ensure_ascii=False))
    return 0 if values.get("ok") else 1


def real_session():
    """The same rule as calendar-helper.py: never the host's Akonadi from a test."""
    if os.environ.get("BUCHHWIN_NESTED") == "1":
        return False
    config = os.environ.get("XDG_CONFIG_HOME", "")
    default = str(pathlib.Path.home() / ".config")
    return not config or os.path.realpath(config) == os.path.realpath(default)


def read_request():
    try:
        text = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not text.strip():
        return {}
    try:
        value = json.loads(text)
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def host_of(url):
    match = HOST.match(str(url or ""))
    return match.group(1).lower() if match else ""


def normalized(url):
    """The link as Akonadi gets it, or "": https only (webcal is https)."""
    text = str(url or "").strip()
    if not text or len(text) > 4096 or re.search(r"\s", text):
        return ""
    text = re.sub(r"^webcals?://", "https://", text, flags=re.IGNORECASE)
    if not REMOTE.match(text) or not host_of(text) or re.match(r"^https://[^/?#]*@", text, re.IGNORECASE):
        return ""
    return "https://" + text[len("https://"):]


def clean_name(name, url):
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(name or "")).strip()[:80]
    return text or host_of(url) or "Calendar"


def redacted(message, path):
    """A status message without the link: the resource writes the file it
    could not load into its message, and that file is the secret."""
    text = str(message or "")
    if path:
        text = text.replace(path, host_of(path) + "/…")
    return re.sub(r"https://([^/\s'\"]+)/[^\s'\"]*", r"https://\1/…", text)


# ---- D-Bus -----------------------------------------------------------------

class Failure(Exception):
    """A call that did not answer as it should. `reason` is the shell's word
    for it, `message` words that are safe to show: never a D-Bus error's
    text, which can carry the resource's file - the link."""

    def __init__(self, reason, message=""):
        super().__init__(message or reason)
        self.reason = reason
        self.message = message


class SessionBus:
    """The calls this helper makes, every one without auto-start."""

    def __init__(self):
        try:
            import dbus  # noqa: PLC0415 - only the real bus needs it
            import dbus.lowlevel  # noqa: PLC0415
        except ImportError as error:
            raise Failure("missingDbus") from error
        self.dbus = dbus
        try:
            self.bus = dbus.SessionBus()
        except dbus.DBusException as error:
            raise Failure("notRunning", "No session bus.") from error

    def call(self, name, path, interface, method, signature="", args=()):
        message = self.dbus.lowlevel.MethodCallMessage(name, path, interface, method)
        message.set_auto_start(False)
        if signature:
            message.append(*args, signature=signature)
        try:
            reply = self.bus.send_message_with_reply_and_block(message, CALL_SECONDS)
        except self.dbus.DBusException as error:
            # The error's name only (org.freedesktop.DBus.Error.UnknownObject).
            raise Failure("dbus", "Akonadi refused it (" + str(error.get_dbus_name() or "no name") + ").") from error
        values = reply.get_args_list()
        return values[0] if len(values) == 1 else values

    def has_owner(self, name):
        try:
            return bool(self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                  "NameHasOwner", "s", (name,)))
        except Failure:
            return False


class Akonadi:
    def __init__(self, bus, sleep=time.sleep, clock=time.monotonic):
        self.bus = bus
        self.sleep = sleep
        self.clock = clock
        if not bus.has_owner(CONTROL):
            raise Failure("notRunning")

    def manager(self, method, signature="", *args):
        return self.bus.call(CONTROL, MANAGER[0], MANAGER[1], method, signature, args)

    def settings(self, instance, method, signature="", *args):
        return self.bus.call(AGENT_PREFIX + instance, SETTINGS[0], SETTINGS[1], method, signature, args)

    def instances(self):
        return [str(item) for item in (self.manager("agentInstances") or [])]

    def path(self, instance):
        """The resource's file, or None when the agent does not answer."""
        if not self.bus.has_owner(AGENT_PREFIX + instance):
            return None
        try:
            return str(self.settings(instance, "path"))
        except Failure:
            return None

    def link_calendars(self):
        rows = []
        for instance in self.instances():
            if not ID.match(instance) or str(self.manager("agentInstanceType", "s", instance)) != TYPE:
                continue
            path = self.path(instance)
            if not path or not REMOTE.match(path):
                continue
            rows.append({
                "id": instance,
                "name": str(self.manager("agentInstanceName", "s", instance) or ""),
                "host": host_of(path),
                "status": int(self.manager("agentInstanceStatus", "s", instance)),
                "online": bool(self.manager("agentInstanceOnline", "s", instance)),
                "message": redacted(self.manager("agentInstanceStatusMessage", "s", instance), path),
            })
        return rows

    def wait_for(self, instance):
        """The new agent's bus name and its settings object, or a Failure."""
        deadline = self.clock() + APPEAR_SECONDS
        while not self.bus.has_owner(AGENT_PREFIX + instance):
            if self.clock() > deadline:
                raise Failure("timeout")
            self.sleep(0.25)
        while True:
            try:
                self.settings(instance, "path")
                return
            except Failure:
                if self.clock() > deadline:
                    raise Failure("timeout") from None
                self.sleep(0.25)

    def add(self, url, name, minutes):
        instance = str(self.manager("createAgentInstance", "s", TYPE) or "")
        if not ID.match(instance):
            raise Failure("dbus", "Akonadi did not make the calendar.")
        try:
            self.wait_for(instance)
            self.settings(instance, "setPath", "s", url)
            self.settings(instance, "setDisplayName", "s", name)
            self.settings(instance, "setReadOnly", "b", True)
            self.settings(instance, "setMonitorFile", "b", False)
            self.settings(instance, "setPeriodicUpdate", "b", True)
            self.settings(instance, "setUpdatePeriod", "i", int(minutes))
            self.settings(instance, "save")
            self.bus.call(AGENT_PREFIX + instance, AGENT_CONTROL[0], AGENT_CONTROL[1], "reconfigure")
            self.manager("setAgentInstanceName", "ss", instance, name)
            self.manager("agentInstanceSynchronize", "s", instance)
        except Failure:
            # Half a calendar is none: the empty resource goes again.
            try:
                self.manager("removeAgentInstance", "s", instance)
            except Failure:
                pass
            raise
        return instance

    def owned(self, instance):
        """Only a link calendar of this type is ever touched: never the
        local std.ics, never another resource."""
        if not ID.match(str(instance or "")) or instance not in self.instances():
            return False
        if str(self.manager("agentInstanceType", "s", instance)) != TYPE:
            return False
        path = self.path(instance)
        return bool(path) and bool(REMOTE.match(path))

    def remove(self, instance):
        if not self.owned(instance):
            raise Failure("notLink")
        self.manager("removeAgentInstance", "s", instance)

    def sync(self, instance):
        if not self.owned(instance):
            raise Failure("notLink")
        self.manager("agentInstanceSynchronize", "s", instance)


# ---- commands --------------------------------------------------------------

def command_list(akonadi, _request):
    return result(ok=True, calendars=akonadi.link_calendars())


def command_add(akonadi, request):
    url = normalized(request.get("url"))
    if not url:
        return result(ok=False, error="That is not an https or webcal link.")
    minutes = request.get("refreshMinutes", DEFAULT_REFRESH)
    if not isinstance(minutes, int) or isinstance(minutes, bool) or not 5 <= minutes <= 1440:
        minutes = DEFAULT_REFRESH
    instance = akonadi.add(url, clean_name(request.get("name"), url), minutes)
    return result(ok=True, id=instance, calendars=akonadi.link_calendars())


def command_remove(akonadi, request):
    akonadi.remove(str(request.get("id") or ""))
    return result(ok=True, calendars=akonadi.link_calendars())


def command_sync(akonadi, request):
    akonadi.sync(str(request.get("id") or ""))
    return result(ok=True, calendars=akonadi.link_calendars())


COMMANDS = {"list": command_list, "add": command_add, "remove": command_remove, "sync": command_sync}


def main(argv=None, bus_factory=SessionBus, sleep=time.sleep, clock=time.monotonic):
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1 or args[0] not in COMMANDS:
        return result(ok=False, error="usage: calendar-link.py list|add|remove|sync")
    if not real_session():
        return result(ok=False, reason="sandbox")
    request = read_request() if args[0] != "list" else {}
    if request is None:
        return result(ok=False, error="The request could not be read.")
    try:
        akonadi = Akonadi(bus_factory(), sleep=sleep, clock=clock)
        return COMMANDS[args[0]](akonadi, request)
    except Failure as failure:
        if failure.message:
            return result(ok=False, reason=failure.reason, error=failure.message)
        return result(ok=False, reason=failure.reason)


if __name__ == "__main__":
    sys.exit(main())
