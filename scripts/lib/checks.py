#!/usr/bin/env python3
"""Static repository checks for buchhwin-shell.

  checks.py json              validate every JSON file in config/ and tests/fixtures/
  checks.py binds             duplicate Hyprland key combinations, two keys for one
                              shell action, and the conf and Lua binding different keys
  checks.py style [--strict]  report hardcoded style values outside theme/
  checks.py handlers          signal handlers using injected parameters, and
                              Connections handlers that match no signal
  checks.py icons             glyphs written out although theme/Icons.qml names them
  checks.py ipc               a property declared inside an IpcHandler, which cannot
                              cross IPC (Quickshell logs "Type QVariant cannot be used")
  checks.py hypr              hyprland.conf, hyprland.lua and HyprAnimations.js drifting apart
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def check_json():
    failed = 0
    files = sorted((ROOT / "config").rglob("*.json"))
    for path in files:
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as error:
            print(f"invalid JSON {path.relative_to(ROOT)}: {error}")
            failed += 1
            continue
        if not isinstance(data, dict) or not isinstance(data.get("configVersion"), int):
            print(f"missing integer configVersion: {path.relative_to(ROOT)}")
            failed += 1
    # Fixtures are parsed too - a test that reads one and gets a parse error
    # fails for the fixture's sake, not its own - except the ones that are
    # broken on purpose, which exist to prove the reader survives them.
    fixtures = sorted((ROOT / "tests" / "fixtures").glob("*.json"))
    for path in fixtures:
        if path.name in BROKEN_FIXTURES:
            continue
        try:
            json.loads(path.read_text())
        except json.JSONDecodeError as error:
            print(f"invalid JSON {path.relative_to(ROOT)}: {error}")
            failed += 1
    print(f"checked {len(files)} config files, {len(fixtures)} fixtures")
    return failed


BROKEN_FIXTURES = {"layout-broken.json"}


def normalize_combo(mods, key):
    parts = {part for part in re.split(r"[\s_+]+", mods.upper()) if part}
    return " ".join(sorted(parts)), key.strip().upper()


# Two keys for one panel is how Super+C and Super+O both ended up toggling the
# control center: the combos differ, so the duplicate check never saw it. Only a
# binding whose whole command is the call counts - a key that adjusts the
# backlight and then asks the shell to re-read it shares that tail on purpose.
IPC_CALL = re.compile(r"^\s*quickshell\s+--path\s+\S+\s+ipc\s+call\s+(.+?)\s*$")
BIND_LINE = re.compile(r"^\s*bind([a-z]*)\s*=\s*(.*)$")


def conf_bind(line):
    """(flags, mods, key, dispatcher, argument) of a bind line, or None.

    The `d` flag puts a description between the key and the dispatcher, so
    the field a dispatcher sits in is not fixed: `bindd = SUPER, D, Launcher,
    exec, ...` has its `exec` fourth, not third, and a reader that counted to
    three took the description for the dispatcher and saw no action at all.
    """
    match = BIND_LINE.match(line)
    if not match:
        return None
    flags, rest = match.groups()
    described = "d" in flags
    parts = [part.strip() for part in rest.split(",", 3 + described)]
    if len(parts) < 3 + described:
        return None
    dispatcher = parts[2 + described]
    argument = parts[3 + described] if len(parts) > 3 + described else ""
    return flags, parts[0], parts[1], dispatcher, argument


def ipc_action(line):
    bind = conf_bind(line)
    if bind is None or bind[3] != "exec":
        return None
    return ipc_action_of(bind[4])


def ipc_action_of(command):
    match = IPC_CALL.match(command)
    return re.sub(r"\s+", " ", match.group(1)) if match else None


def conf_binds():
    """[(namespace, combo, action, where)] for every bind in hypr/*.conf."""
    found = []
    for conf in sorted((ROOT / "hypr").glob("*.conf")):
        for number, line in enumerate(conf.read_text().splitlines(), 1):
            bind = conf_bind(line.split("#", 1)[0])
            if bind is None:
                continue
            flags, mods, key, dispatcher, argument = bind
            combo = normalize_combo(mods, key)
            # Mouse bindings (bindm) live in a separate namespace from key presses.
            namespace = ("mouse" if "m" in flags else "key",) + combo
            action = ipc_action_of(argument) if dispatcher == "exec" else None
            found.append((namespace, combo, action, f"{conf.name}:{number}"))
    return found


# ---- the same bindings, in the Lua dialect ---------------------------------
# `hl.bind(keyFor("SUPER + D"), exec(ipc .. "launcher toggle"), { ... })`, and
# inside `for i = 1, 9 do ... end` a combo of `"SUPER + " .. i`. Every call is
# read as text, never run: the first argument is the combo, the second is the
# action when it is an `exec(...)` whose command concatenates literals, the
# `ipc` prefix and the loop variable, and the options table says whether it is
# a mouse binding.
LUA_FOR = re.compile(r"^[ \t]*for\s+(\w+)\s*=\s*(-?\d+)\s*,\s*(-?\d+)\s*do\b(.*?)^[ \t]*end\b", re.M | re.S)
LUA_IPC_PREFIX = "quickshell --path $projectPath ipc call "


def _lua_call_args(text, start):
    """The argument text of the call whose `(` is at `start`, string-aware."""
    depth = 0
    quote = ""
    index = start
    while index < len(text):
        char = text[index]
        if quote:
            if char == "\\":
                index += 1
            elif char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
        index += 1
    return text[start + 1:]


def _lua_split_args(args):
    """Top-level comma-separated arguments of a call."""
    parts = []
    depth = 0
    quote = ""
    current = []
    for char in args:
        if quote:
            current.append(char)
            if char == quote:
                quote = ""
            continue
        if char in "\"'":
            quote = char
        elif char in "({[":
            depth += 1
        elif char in ")}]":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    if "".join(current).strip():
        parts.append("".join(current).strip())
    return parts


def _lua_concat(expression, names):
    """A `..` concatenation of literals and names, as text; None if unknown."""
    out = []
    for piece in re.split(r"\s*\.\.\s*", expression.strip()):
        literal = re.fullmatch(r"\"((?:[^\"\\]|\\.)*)\"", piece)
        if literal:
            out.append(literal.group(1))
        elif piece in names:
            out.append(str(names[piece]))
        elif re.fullmatch(r"\w+", piece):
            out.append("$" + piece)
        else:
            return None
    return "".join(out)


def lua_binds(text):
    """[(namespace, combo, action, where)] for every hl.bind in the Lua config."""
    source = _strip_lua_comments(text)
    loops = [(match.start(4), match.end(4), match.group(1), int(match.group(2)), int(match.group(3)))
             for match in LUA_FOR.finditer(source)]
    found = []
    for match in re.finditer(r"\bhl\.bind\s*\(", source):
        args = _lua_split_args(_lua_call_args(source, match.end() - 1))
        if len(args) < 2:
            continue
        where = f"hyprland.lua:{source.count(chr(10), 0, match.start()) + 1}"
        combo_text = args[0]
        wrapped = re.fullmatch(r"keyFor\s*\((.*)\)", combo_text, re.S)
        if wrapped:
            combo_text = wrapped.group(1)
        exec_call = re.fullmatch(r"exec\s*\((.*)\)", args[1], re.S)
        options = args[2] if len(args) > 2 else ""
        kind = "mouse" if re.search(r"\bmouse\s*=\s*true\b", options) else "key"
        rounds = [{}]
        for start, end, name, low, high in loops:
            if start <= match.start() < end:
                rounds = [{name: value} for value in range(low, high + 1)]
        for names in rounds:
            combo = _lua_concat(combo_text, dict(names, ipc=LUA_IPC_PREFIX))
            if combo is None:
                continue
            parts = combo.split("+")
            normalized = normalize_combo(" ".join(parts[:-1]), parts[-1])
            action = None
            if exec_call:
                command = _lua_concat(exec_call.group(1), dict(names, ipc=LUA_IPC_PREFIX))
                action = ipc_action_of(command) if command is not None else None
            found.append(((kind,) + normalized, normalized, action, where))
    return found


def _bind_problems(binds):
    """Duplicate combos and two combos for one shell action, in one dialect."""
    seen = {}
    actions = {}
    problems = []
    for namespace, combo, action, where in binds:
        if namespace in seen:
            problems.append(f"duplicate binding {' + '.join(filter(None, combo))} at {where} and {seen[namespace]}")
        else:
            seen[namespace] = where
        if action is None:
            continue
        if action in actions:
            problems.append(f"two bindings call the same action '{action}' at {where} and {actions[action]}")
        else:
            actions[action] = where
    return problems, seen, actions


def bind_drift(conf, lua):
    """The two dialects binding different keys, or one key to different actions.

    The Lua's nine-workspace loop is two `hl.bind` lines for eighteen bindings,
    which is why a count of the calls (60) never matched a count of the conf
    lines (76); expanded, the sets are the same and this holds them so.
    """
    problems = []
    conf_keys = {namespace: where for namespace, _, _, where in conf}
    lua_keys = {namespace: where for namespace, _, _, where in lua}
    for namespace in sorted(set(conf_keys) - set(lua_keys)):
        problems.append(f"{' + '.join(filter(None, namespace[1:]))}: bound only in the conf ({conf_keys[namespace]})")
    for namespace in sorted(set(lua_keys) - set(conf_keys)):
        problems.append(f"{' + '.join(filter(None, namespace[1:]))}: bound only in the Lua ({lua_keys[namespace]})")
    conf_actions = {namespace: action for namespace, _, action, _ in conf}
    for namespace, _, action, where in lua:
        if namespace in conf_actions and conf_actions[namespace] != action:
            problems.append(f"{' + '.join(filter(None, namespace[1:]))}: conf calls {conf_actions[namespace]!r}, Lua calls {action!r} ({where})")
    return problems


def check_binds():
    conf = conf_binds()
    lua = lua_binds((ROOT / "hypr" / "hyprland.lua").read_text())
    problems, seen, actions = _bind_problems(conf)
    lua_problems, lua_seen, lua_actions = _bind_problems(lua)
    problems += lua_problems
    problems += bind_drift(conf, lua)
    for problem in problems:
        print(problem)
    print(f"checked {len(seen)} conf and {len(lua_seen)} Lua bindings, {len(actions)} and {len(lua_actions)} shell actions")
    return len(problems)


STYLE_PATTERNS = [
    ("color literal", re.compile(r"[\"']#[0-9a-fA-F]{3,8}[\"']")),
    # Qt.rgba() is the most common way to write a colour in this repo and used
    # to be invisible to this check.
    ("colour built at the call site", re.compile(r"Qt\.(rgba|hsla|hsva)\(")),
    ("named colour", re.compile(r":\s*[\"'](white|black|red|green|blue|yellow|gray|grey|transparent)[\"']")),
    ("font family literal", re.compile(r"font\.family:\s*\"")),
    ("numeric duration", re.compile(r"\bduration:\s*\d")),
    ("numeric radius", re.compile(r"\bradius:\s*\d")),
    ("numeric font size", re.compile(r"font\.pixelSize:\s*\d")),
    ("numeric spacing", re.compile(r"\b(spacing|padding|leftPadding|rightPadding|topPadding|bottomPadding):\s*\d*[1-9]")),
    ("numeric margin", re.compile(r"\b(anchors\.\w*[Mm]argins?|Layout\.\w*[Mm]argins?):\s*\d*[1-9]")),
    ("numeric border width", re.compile(r"\bborder\.width:\s*\d*[1-9]")),
    ("shadow literal", re.compile(r"\b(shadowBlur|shadowVerticalOffset|shadowHorizontalOffset|blurMax):\s*[\d.]")),
    ("letter spacing literal", re.compile(r"font\.letterSpacing:\s*[\d.-]")),
]

# "transparent" is a real value, not a colour choice, and 0 spacing or margins
# say "none" rather than picking a size. A line that ends in `// style: <reason>`
# is a deliberate exception and has to say why.
STYLE_ALLOW = re.compile(r':\s*"transparent"|:\s*0\b|//\s*style:\s*\S')

# theme/ owns the values; tests/ and fixtures/ assert against literals on
# purpose; the SDDM theme cannot import the singletons (its own drift is
# checked by tests/qml/SddmThemeTest.qml).
STYLE_ROOTS = ["shell", "services", "shell.qml", "lock.qml"]

# These own a palette of their own rather than the shell's look: the terminal
# writes colours into Kitty and Starship configs, and the contrast helper is
# maths over colours, not a choice of them.
STYLE_SKIP = ("services/terminal/", "services/appearance/ContrastLogic.js")


def _style_files():
    for entry in STYLE_ROOTS:
        path = ROOT / entry
        if path.is_file():
            yield path
        else:
            for found in sorted(path.rglob("*.qml")):
                yield found
            for found in sorted(path.rglob("*.js")):
                yield found


# A glyph the theme has a name for must not be written out again. Banning every
# glyph would be wrong - a weather condition or a battery level is data, and it
# belongs with the service that knows what it describes - but "remove" once was
# a cross in one half of a file and a trash can in the other, and that is what
# theme/Icons.qml exists to stop.
ICON_NAME = re.compile(r'readonly property string (\w+): "(.+?)"')


def named_icons():
    text = (ROOT / "theme" / "Icons.qml").read_text()
    return {match.group(2): match.group(1) for match in ICON_NAME.finditer(text)}


def check_icons():
    icons = named_icons()
    failed = 0
    for path in sorted(list((ROOT / "shell").rglob("*.qml")) + list((ROOT / "services").rglob("*.qml"))):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            # Only the allowed token is taken out, not the line around it:
            # `x: 0; text: "<glyph>"` used to pass because the `: 0` made the
            # whole line invisible.
            rest = STYLE_ALLOW.sub("", line)
            for glyph, name in icons.items():
                if '"%s"' % glyph in rest:
                    print("%s:%d uses the glyph of Icons.%s instead of the name"
                          % (path.relative_to(ROOT), number, name))
                    failed += 1
    print("checked %d named glyphs" % len(icons))
    return failed


def check_style(strict):
    total = 0
    for path in _style_files():
        relative = path.relative_to(ROOT).as_posix()
        if any(relative.startswith(skip) for skip in STYLE_SKIP):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for label, pattern in STYLE_PATTERNS:
                if pattern.search(line) and not STYLE_ALLOW.search(line):
                    total += 1
                    if strict:
                        print(f"{path.relative_to(ROOT)}:{number}: {label}: {stripped}")
                    break
    print(f"hardcoded style values outside theme/: {total}")
    return total if strict else 0


# Qt 6 deprecates parameters injected into signal handlers ("Parameter "mouse"
# is not declared"); handlers must declare them: `onClicked: mouse => ...` or
# `function onClicked(mouse) {}`. `drag` is a MouseArea property, not a parameter.
INJECTED_NAMES = ("mouse", "wheel", "event", "drop", "eventPoint")
HANDLER = re.compile(r"(?<![\w.])((?:[A-Z]\w*\.)?on[A-Z]\w*)\s*:\s*")


def strip_code(text):
    """Remove string literals and comments so their words are not matched.

    One pass rather than three substitutions, because strings and comments are
    not independent: run the string pattern first and an apostrophe in a
    comment - "the user's list" - opens a string that swallows everything up to
    the next one, and run the comment pattern first and a `//` inside a URL
    eats the rest of the line. Either way whole files went blind, and silently:
    the checks kept printing a count and finding nothing. Newlines are kept so
    line numbers still hold.
    """
    out = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char == "/" and text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
        elif char == "/" and text.startswith("/*", index):
            end = text.find("*/", index + 2)
            chunk = text[index:length if end < 0 else end + 2]
            out.append("\n" * chunk.count("\n"))
            index = length if end < 0 else end + 2
        elif char in "\"'`":
            quote = char
            index += 1
            while index < length and text[index] != quote:
                index += 2 if text[index] == "\\" else 1
            index += 1
            out.append('""')
        else:
            out.append(char)
            index += 1
    return "".join(out)


def handler_body(text, start):
    """The expression or {} block of a handler starting at `start`."""
    if text.startswith("{", start):
        depth = 0
        for index in range(start, len(text)):
            depth += {"{": 1, "}": -1}.get(text[index], 0)
            if depth == 0:
                return text[start:index + 1]
        return text[start:]
    end = text.find("\n", start)
    return text[start:] if end < 0 else text[start:end]


def injected_parameter_uses(source):
    """[(line, handler, name)] for handlers that use an undeclared parameter."""
    text = strip_code(source)
    ids = set(re.findall(r"\bid:\s*(\w+)", text))
    found = []
    for match in HANDLER.finditer(text):
        body = handler_body(text, match.end())
        if re.match(r"(function\b|\(?\s*[\w\s,]*\)?\s*=>)", body):
            continue
        declared = set(re.findall(r"\b(?:const|let|var)\s+(\w+)", body))
        declared |= {name for params in re.findall(r"\(([\w\s,]*)\)\s*=>|\b(\w+)\s*=>|function\s*\w*\s*\(([\w\s,]*)\)", body)
                     for group in params for name in re.split(r"[\s,]+", group) if name}
        names = set(re.findall(r"(?<![\w.])(" + "|".join(INJECTED_NAMES) + r")\b", body)) - ids - declared
        line = text.count("\n", 0, match.start()) + 1
        found.extend((line, match.group(1), name) for name in sorted(names))
    return found


# ---- Connections against a singleton ---------------------------------------
# `Connections { target: SomeService; function onFooChanged() {} }` is a no-op
# when the singleton has no `foo`. Qt says so at runtime, in a warning nobody
# reads, and the handler simply never fires - which is how renaming
# LayoutService.mode to desktopMode left the layout editor's selection handler
# orphaned. Only the session smoke test caught it, and only because it reads
# the log.
#
# Deliberately narrow: a `target:` that is a bare name of a `pragma Singleton`
# file under services/ or theme/, nothing else. An id, an expression or a type
# this does not know about is skipped rather than guessed at.
CONNECTIONS = re.compile(r"\bConnections\s*\{")
TARGET = re.compile(r"\btarget:\s*([A-Z]\w*)\s*(?:\n|;|$)")
CONNECTION_HANDLER = re.compile(r"\bfunction\s+(on[A-Z]\w*)\s*\(")


def singleton_members(path):
    """Property and signal names a `pragma Singleton` file declares, or None."""
    text = strip_code(path.read_text())
    if not re.search(r"^\s*pragma\s+Singleton\b", text, re.M):
        return None
    names = set(re.findall(r"\bproperty\s+(?:alias\s+)?[\w.<>]+\s+(\w+)", text))
    names |= set(re.findall(r"\bproperty\s+alias\s+(\w+)\s*:", text))
    names |= set(re.findall(r"\bsignal\s+(\w+)", text))
    return names


def singleton_table():
    table = {}
    for folder in ("services", "theme"):
        for path in (ROOT / folder).rglob("*.qml"):
            members = singleton_members(path)
            if members is not None:
                table[path.stem] = members
    return table


def block_body(text, start):
    """The {} block starting at `start` (the index of the brace)."""
    depth = 0
    for index in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[start:index + 1]
    return text[start:]


def orphan_connections(source, table):
    """[(line, target, handler, member)] for handlers no signal matches."""
    text = strip_code(source)
    found = []
    for match in CONNECTIONS.finditer(text):
        body = block_body(text, match.end() - 1)
        target = TARGET.search(body)
        if not target or target.group(1) not in table:
            continue
        members = table[target.group(1)]
        for handler in CONNECTION_HANDLER.finditer(body):
            name = handler.group(1)[2:]
            member = name[0].lower() + name[1:]
            # `onFooChanged` needs a `foo`; `onFoo` needs a signal `foo`.
            wanted = member[:-len("Changed")] if member.endswith("Changed") else member
            if wanted in members or member in members:
                continue
            # `body` starts at the brace, which is match.end() - 1.
            line = text.count("\n", 0, match.end() - 1 + handler.start()) + 1
            found.append((line, target.group(1), handler.group(1), wanted))
    return found


# ---- HyprCompat.commands: the table the shell reaches Hyprland through -----
# `HyprCompat.commands` is a hand-written table of the functions in
# services/hypr/HyprCommands.js the shell may call. A function added to the
# .js and used through the table without an entry is a TypeError the smoke
# test finds in the nested session's log, and nothing before that: the
# workspace move of 2026-09-23 got that far. So every `HyprCompat.commands.x`
# in QML must be a key of the table, and every key must name a function the
# .js defines.
COMMAND_USE = re.compile(r"\bHyprCompat\.commands\.(\w+)")


def compat_table(compat_source, commands_source):
    """({key: function} of the `commands` table, {functions the .js defines})."""
    text = strip_code(compat_source)
    match = re.search(r"\bproperty\s+var\s+commands\s*:\s*\(\s*\{", text)
    if not match:
        return None, set()
    body = block_body(text, match.end() - 1)
    keys = dict(re.findall(r"(\w+)\s*:\s*Commands\.(\w+)", body))
    # The .js is not run through strip_code: its regex literals hold quote
    # characters (`/"/g`) that read as strings and swallow whole functions.
    # A `.pragma library` file defines its functions at column 0, and that is
    # enough to find them.
    functions = set(re.findall(r"^function\s+(\w+)\s*\(", commands_source, re.M))
    return keys, functions


def compat_problems(compat_source, commands_source, sources):
    """[(path, line, message)] for table entries and uses that do not resolve.

    `sources` is {path: text} of every QML file that may use the table.
    """
    keys, functions = compat_table(compat_source, commands_source)
    problems = []
    if keys is None:
        return [("services/HyprCompat.qml", 0, "no `property var commands: ({ … })` table found")]
    for key, function in keys.items():
        if function not in functions:
            problems.append(("services/HyprCompat.qml", 0, f"commands.{key} points at Commands.{function}, which HyprCommands.js does not define"))
    for path, source in sorted(sources.items()):
        text = strip_code(source)
        for match in COMMAND_USE.finditer(text):
            name = match.group(1)
            if name in keys:
                continue
            line = text.count("\n", 0, match.start()) + 1
            problems.append((path, line, f"HyprCompat.commands.{name} is not in the commands table of services/HyprCompat.qml; it is a TypeError at run time"))
    return problems


def check_handlers():
    failed = 0
    files = sorted(path for folder in ("shell", "services", "theme") for path in (ROOT / folder).rglob("*.qml"))
    files += sorted(ROOT.glob("*.qml"))
    for path in files:
        for line, handler, name in injected_parameter_uses(path.read_text()):
            print(f"{path.relative_to(ROOT)}:{line}: {handler} uses injected parameter '{name}'; declare it ({handler.split('.')[-1]}: {name} => ...)")
            failed += 1
    table = singleton_table()
    connections = 0
    for path in files:
        for line, target, handler, member in orphan_connections(path.read_text(), table):
            print(f"{path.relative_to(ROOT)}:{line}: {handler} on {target}, which has no '{member}'; the handler never fires")
            failed += 1
        connections += 1
    compat = (ROOT / "services" / "HyprCompat.qml").read_text()
    commands = (ROOT / "services" / "hypr" / "HyprCommands.js").read_text()
    sources = {str(path.relative_to(ROOT)): path.read_text() for path in files}
    problems = compat_problems(compat, commands, sources)
    for path, line, message in problems:
        print(f"{path}:{line}: {message}")
    failed += len(problems)
    keys = compat_table(compat, commands)[0] or {}
    print(f"checked signal handlers in {len(files)} QML files, against {len(table)} singletons, and {len(keys)} HyprCompat commands")
    return failed


# ---- IpcHandler: what shell.qml exports ------------------------------------
# An IpcHandler exports every property it declares, and a QML `var` (a list,
# an object) cannot cross IPC: Quickshell logs "Type QVariant cannot be used
# across IPC" at load, once per property, and the smoke test reads that out of
# the log while a unit test never would. shell.qml says so at the `popup`
# handler and keeps a plain function there instead; this holds the rest to it.
# The targets are also read here, for tests/python/smoke_targets_test.py,
# which holds the smoke test's expected list to what shell.qml declares.
IPC_HANDLER = re.compile(r"\bIpcHandler\s*\{")
PROPERTY = re.compile(r"^[ \t]*(?:(?:readonly|required|default)\s+)*property\s+[\w.<>]+\s+(\w+)", re.M)


def blank_code(text):
    """strip_code with the length kept: removed characters become spaces.

    A match found in the blank text is at the same offset in the source, so
    what strip_code throws away - the string literals - can be read back from
    it. Quotes are kept, their contents blanked; newlines are kept everywhere.
    """
    out = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char == "/" and text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            out.append(" " * (end - index))
            index = end
        elif char == "/" and text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end < 0 else end + 2
            out.append("".join("\n" if c == "\n" else " " for c in text[index:end]))
            index = end
        elif char in "\"'`":
            quote = char
            start = index
            index += 1
            while index < length and text[index] != quote:
                index += 2 if text[index] == "\\" else 1
            index = min(length, index + 1)
            chunk = text[start:index]
            closed = len(chunk) > 1 and chunk.endswith(quote)
            inside = chunk[1:-1] if closed else chunk[1:]
            out.append(quote + "".join("\n" if c == "\n" else " " for c in inside) + (quote if closed else ""))
        else:
            out.append(char)
            index += 1
    return "".join(out)


def _depth(body, offset):
    """How many braces deep `offset` is inside a block that starts with one."""
    return body.count("{", 0, offset) - body.count("}", 0, offset)


def ipc_handlers(source):
    """[(line, target, start, end)] for every IpcHandler block in `source`.

    `start` and `end` bound the {} body in `source`; the target is the string
    the block's own `target:` names, or "" when it has none.
    """
    blank = blank_code(source)
    found = []
    for match in IPC_HANDLER.finditer(blank):
        start = match.end() - 1
        body = block_body(blank, start)
        end = start + len(body)
        target = ""
        for candidate in re.finditer(r'\btarget:\s*"', body):
            if _depth(body, candidate.start()) == 1:
                quote = start + candidate.end()
                target = source[quote:source.find('"', quote)]
                break
        found.append((blank.count("\n", 0, match.start()) + 1, target, start, end))
    return found


def ipc_targets(source):
    """The targets the IpcHandlers in `source` declare, in file order."""
    return [target for _, target, _, _ in ipc_handlers(source) if target]


def ipc_properties(source):
    """[(line, target, name)] for properties declared directly in an IpcHandler."""
    blank = blank_code(source)
    found = []
    for line, target, start, end in ipc_handlers(source):
        body = blank[start:end]
        for match in PROPERTY.finditer(body):
            if _depth(body, match.start()) != 1:
                continue
            found.append((line + body.count("\n", 0, match.start()), target, match.group(1)))
    return found


def check_ipc():
    failed = 0
    path = ROOT / "shell.qml"
    source = path.read_text()
    for line, target, name in ipc_properties(source):
        print(f"{path.relative_to(ROOT)}:{line}: IpcHandler '{target}' declares property '{name}', which is exported over IPC and a var cannot cross it; make it a function")
        failed += 1
    print(f"checked {len(ipc_handlers(source))} IpcHandlers in shell.qml")
    return failed


# ---- Hyprland: two dialects and a runtime copy of the same numbers ----------
# hypr/hyprland.conf and hypr/hyprland.lua are the same session written twice,
# and services/hypr/HyprAnimations.js is a third copy of the animation table
# that the shell re-emits when the animation mode changes. Nothing held them
# together: `--verify-config` only says each file parses on its own.
#
# Deliberately narrow. Only the look-and-feel scalars and the animation table
# are compared, because those are what a design change touches in one file and
# forgets in the other. Bindings stay out of this one: checks.py binds reads
# both dialects with a parser of their own and holds them to the same keys.
#
# `render` and `animations` are in the list because they were not: the frame
# scheduling flag and the animations switch are the two settings the shell
# itself re-emits at runtime, and neither was being compared.
HYPR_SECTIONS = ("general", "decoration", "misc", "input", "dwindle", "xwayland", "render", "animations")
# Legitimately different between the two files, with the reason.
HYPR_ALLOWED = {
    # The conf spells the nested blur/shadow blocks inline; the Lua nests them
    # as tables and the flattener already agrees on the key, so nothing here
    # yet. Kept as the place to put a difference that is meant.
}


def _hypr_number(text):
    try:
        value = float(text)
    except ValueError:
        return text.strip()
    return round(value, 4)


def _hypr_conf(text):
    """section:key -> value, plus animation:<leaf> and bezier:<name>."""
    values = {}
    stack = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.endswith("{"):
            stack.append(line[:-1].strip())
            continue
        if line == "}":
            if stack:
                stack.pop()
            continue
        if "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key == "animation":
            parts = [part.strip() for part in value.split(",")]
            # The speed is a number in both files but spelled `1` in one and
            # `1.0` in the other; the style is text and stays as it is.
            tail = [parts[1]] + [_fmt(parts[2])] + parts[3:] if len(parts) > 2 else parts[1:]
            values["animation:" + parts[0]] = ",".join(tail)
            continue
        if key == "bezier":
            parts = [part.strip() for part in value.split(",")]
            values["bezier:" + parts[0]] = ",".join(_fmt(part) for part in parts[1:])
            continue
        if not stack or stack[0] not in HYPR_SECTIONS:
            continue
        path = ":".join(stack + key.replace("-", "_").split("."))
        values[path] = _hypr_number(value)
    return values


def _fmt(text):
    value = _hypr_number(text)
    return str(value)


def _strip_lua_comments(text):
    """Lua without its `--` and `--[[ ]]` comments; newlines and strings kept.

    A comment that mentions `size = 6` is not a setting, and the config
    parser used to read it as one. Strings are walked over rather than
    searched, so a `--` inside one stays what it is.
    """
    out = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char in "\"'":
            end = index + 1
            while end < length and text[end] != char:
                end += 2 if text[end] == "\\" else 1
            out.append(text[index:end + 1])
            index = end + 1
        elif text.startswith("--[[", index):
            end = text.find("]]", index + 4)
            chunk = text[index:length if end < 0 else end + 2]
            out.append("\n" * chunk.count("\n"))
            index = length if end < 0 else end + 2
        elif text.startswith("--", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
        else:
            out.append(char)
            index += 1
    return "".join(out)


def _hypr_lua(source):
    """The same map, from hl.config / hl.animation / hl.curve."""
    text = _strip_lua_comments(source)
    values = {}
    for match in re.finditer(r"hl\.animation\(\{([^}]*)\}\)", text):
        fields = _lua_fields(match.group(1))
        leaf = fields.get("leaf", "").strip('"')
        if not leaf:
            continue
        parts = ["1" if fields.get("enabled") == "true" else "0",
                 _fmt(fields.get("speed", "0")), fields.get("bezier", "").strip('"')]
        style = fields.get("style", "").strip('"')
        if style:
            parts.append(style)
        values["animation:" + leaf] = ",".join(parts)
    for match in re.finditer(r"hl\.curve\(\s*\"([^\"]+)\"\s*,\s*\{(.*?)\}\s*\)\s*$",
                             text, re.M | re.S):
        numbers = re.findall(r"-?\d+(?:\.\d+)?", match.group(2))
        values["bezier:" + match.group(1)] = ",".join(_fmt(number) for number in numbers)
    # The table is taken by brace count, not by a pattern that runs to the
    # last `})` in the file - which is a window rule's, so the "config" used
    # to be most of the file.
    config = re.search(r"hl\.config\(\s*\{", text)
    if config:
        table = _lua_block(text, config.end() - 1)
        for section in HYPR_SECTIONS:
            block = re.search(r"\b" + section + r"\s*=\s*\{", table)
            if not block:
                continue
            body = _lua_block(table, block.end() - 1)
            _lua_scalars(body, [section], values)
    return values


def _lua_block(text, start):
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    return ""


def _lua_fields(body):
    fields = {}
    for match in re.finditer(r"(\w+)\s*=\s*(\"[^\"]*\"|[-\w.]+)", body):
        fields[match.group(1)] = match.group(2)
    return fields


def _lua_scalars(body, path, values):
    index = 0
    while index < len(body):
        match = re.compile(r"(\w+)\s*=\s*").search(body, index)
        if not match:
            break
        name = match.group(1)
        rest = body[match.end():].lstrip()
        offset = match.end() + (len(body[match.end():]) - len(rest))
        if rest.startswith("{"):
            inner = _lua_block(body, offset)
            _lua_scalars(inner, path + [name], values)
            index = offset + len(inner) + 2
            continue
        value = re.match(r"(\"[^\"]*\"|[-\w.%()]+)", rest)
        if value:
            values[":".join(path + [name])] = _hypr_number(value.group(1).strip('"'))
            index = offset + value.end()
        else:
            index = offset
    return values


def _conf_layer_rules(text):
    """layer:<namespace>:<property> -> value, from `layerrule = ...` lines."""
    values = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line.startswith("layerrule"):
            continue
        _, _, body = line.partition("=")
        effect, _, match = body.partition(",")
        namespace = re.search(r"namespace\s+(\S+)", match)
        if not namespace:
            continue
        parts = effect.strip().split()
        if not parts:
            continue
        name = parts[0]
        value = " ".join(parts[1:])
        if value in ("on", "true"):
            value = "1"
        elif value in ("off", "false"):
            value = "0"
        values[f"layer:{namespace.group(1)}:{name}"] = _fmt(value) if value else "1"
    return values


def _lua_layer_rules(text):
    """The same map, from hl.layer_rule."""
    values = {}
    for match in re.finditer(r"hl\.layer_rule\(\{(.*?)\}\s*\)", text, re.S):
        fields = _lua_fields(match.group(1))
        namespace = fields.get("namespace", "").strip('"')
        if not namespace:
            continue
        for name, value in fields.items():
            if name in ("name", "namespace", "class", "title"):
                continue
            value = value.strip('"')
            if value == "true":
                value = "1"
            elif value == "false":
                value = "0"
            values[f"layer:{namespace}:{name}"] = _fmt(value)
    return values


def check_hypr():
    conf = _hypr_conf((ROOT / "hypr" / "hyprland.conf").read_text())
    lua = _hypr_lua((ROOT / "hypr" / "hyprland.lua").read_text())

    # Layer rules, which this check could not see for a long time and which
    # therefore drifted: `blur off` for the screen corners was written into the
    # Lua dialect only, so a legacy session went on blurring every monitor on
    # every frame behind four rounded corners - the very defect the comment
    # beside that rule describes as fixed. They live in `windowrules.conf`,
    # which `hyprland.conf` sources, so both files are read here.
    conf_text = "\n".join((ROOT / "hypr" / name).read_text()
                          for name in ("hyprland.conf", "windowrules.conf"))
    lua_text = (ROOT / "hypr" / "hyprland.lua").read_text()
    conf.update(_conf_layer_rules(conf_text))
    lua.update(_lua_layer_rules(lua_text))

    problems = hypr_drift(conf, lua)

    # The shell's own copy of the animation table, which it re-emits when the
    # animation mode changes. A leaf that drifts here is a mode switch that
    # silently changes the look.
    source = (ROOT / "services" / "hypr" / "HyprAnimations.js").read_text()
    problems += animation_drift(conf, source)

    # The shell's own copy of the compositor's outer gap. A surface that wants
    # room under itself reserves that much less, because Hyprland already
    # leaves it - so the two drifting apart moves every panel by a few pixels
    # and nothing says why.
    metrics = (ROOT / "theme" / "Metrics.qml").read_text()
    match = re.search(r"readonly property int windowGap:\s*(\d+)", metrics)
    if not match:
        problems.append("theme/Metrics.qml: no windowGap")
    elif "general:gaps_out" not in conf:
        problems.append("hyprland.conf: no general:gaps_out for windowGap to match")
    elif _fmt(conf["general:gaps_out"]) != _fmt(match.group(1)):
        problems.append(f"windowGap: Metrics {match.group(1)} vs gaps_out {conf['general:gaps_out']}")

    for problem in problems:
        print(problem)
    print(f"compared {len(set(conf) | set(lua))} Hyprland settings across both dialects")
    return bool(problems)


def hypr_drift(conf, lua):
    """Keys the two parsed dialects disagree on, as messages."""
    problems = []
    for key in sorted(set(conf) | set(lua)):
        if key in HYPR_ALLOWED:
            continue
        if key not in lua:
            problems.append(f"{key}: only in hyprland.conf ({conf[key]})")
        elif key not in conf:
            problems.append(f"{key}: only in hyprland.lua ({lua[key]})")
        elif str(conf[key]) != str(lua[key]):
            problems.append(f"{key}: conf {conf[key]!r} vs lua {lua[key]!r}")
    return problems


def animation_table(source):
    """[{leaf, speed, bezier, style, off}] from HyprAnimations.js's BASE.

    Each `{ ... }` entry is read by field name, in whatever order the fields
    are written. A table that names more `leaf:`s than entries parsed is an
    entry written in a shape this cannot read, and that is an error rather
    than a shorter table: a leaf that is not read is a leaf that is not
    compared.
    """
    stripped = strip_comments_only(source)
    base = re.search(r"\bBASE\s*=\s*\[", stripped)
    if not base:
        raise ValueError("HyprAnimations.js has no BASE table")
    text = _bracket_block(stripped, base.end() - 1)
    entries = []
    for match in re.finditer(r"\{([^{}]*)\}", text):
        fields = {}
        for field in re.finditer(r"(\w+)\s*:\s*(\"[^\"]*\"|[-\w.]+)", match.group(1)):
            fields[field.group(1)] = field.group(2).strip('"')
        if not fields.get("leaf"):
            continue
        entries.append({"leaf": fields["leaf"], "speed": fields.get("speed", "0"),
                        "bezier": fields.get("bezier", ""), "style": fields.get("style", ""),
                        "off": fields.get("off") == "true"})
    leaves = len(re.findall(r"\bleaf\s*:", text))
    if leaves != len(entries):
        raise ValueError(f"HyprAnimations.js names {leaves} leaves but {len(entries)} entries were read")
    return entries


def _bracket_block(text, start):
    """The `[...]` starting at `start`, brackets balanced."""
    depth = 0
    for index in range(start, len(text)):
        depth += {"[": 1, "]": -1}.get(text[index], 0)
        if depth == 0:
            return text[start:index + 1]
    return text[start:]


def strip_comments_only(text):
    """JS without its comments; string literals are kept as written."""
    out = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = length if end < 0 else end + 2
        elif char in "\"'`":
            end = index + 1
            while end < length and text[end] != char:
                end += 2 if text[end] == "\\" else 1
            out.append(text[index:end + 1])
            index = end + 1
        else:
            out.append(char)
            index += 1
    return "".join(out)


def animation_drift(conf, source):
    """The animation leaves the conf and HyprAnimations.js disagree on.

    Both directions: a leaf the table has and the conf lacks, and a leaf the
    conf has and the table lacks - which is the one that was never reported,
    so an `animation = X` line in both config files and missing from BASE
    was a leaf the shell's mode switch silently left at whatever it was.
    """
    problems = []
    try:
        entries = animation_table(source)
    except ValueError as error:
        return [str(error)]
    table = {}
    for entry in entries:
        key = "animation:" + entry["leaf"]
        parts = ["0" if entry["off"] else "1", _fmt(entry["speed"]), entry["bezier"]]
        if entry["style"]:
            parts.append(entry["style"])
        table[key] = ",".join(parts)
    for key in sorted(set(table) | {key for key in conf if key.startswith("animation:")}):
        if key not in conf:
            problems.append(f"{key}: in HyprAnimations.js but not in hyprland.conf")
        elif key not in table:
            problems.append(f"{key}: in hyprland.conf but not in HyprAnimations.js")
        elif conf[key] != table[key]:
            problems.append(f"{key}: HyprAnimations.js {table[key]!r} vs hyprland.conf {conf[key]!r}")
    return problems


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    command = argv[0]
    if command == "json":
        return 1 if check_json() else 0
    if command == "binds":
        return 1 if check_binds() else 0
    if command == "style":
        return 1 if check_style("--strict" in argv[1:]) else 0
    if command == "handlers":
        return 1 if check_handlers() else 0
    if command == "icons":
        return 1 if check_icons() else 0
    if command == "ipc":
        return 1 if check_ipc() else 0
    if command == "hypr":
        return 1 if check_hypr() else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
