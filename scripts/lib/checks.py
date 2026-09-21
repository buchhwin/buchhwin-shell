#!/usr/bin/env python3
"""Static repository checks for buchhwin-shell.

  checks.py json              validate every JSON file in config/ and tests/fixtures/
  checks.py binds             detect duplicate Hyprland key combinations
  checks.py style [--strict]  report hardcoded style values outside theme/
  checks.py handlers          signal handlers using injected parameters
  checks.py icons             glyphs written out although theme/Icons.qml names them
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
    # Fixtures may be deliberately broken; they only have to exist.
    fixtures = sorted((ROOT / "tests" / "fixtures").glob("*.json"))
    print(f"checked {len(files)} config files, {len(fixtures)} fixtures")
    return failed


def normalize_combo(mods, key):
    parts = {part for part in re.split(r"[\s_+]+", mods.upper()) if part}
    return " ".join(sorted(parts)), key.strip().upper()


# Two keys for one panel is how Super+C and Super+O both ended up toggling the
# control center: the combos differ, so the duplicate check never saw it. Only a
# binding whose whole command is the call counts - a key that adjusts the
# backlight and then asks the shell to re-read it shares that tail on purpose.
IPC_CALL = re.compile(r"^\s*quickshell\s+--path\s+\S+\s+ipc\s+call\s+(.+?)\s*$")


def ipc_action(line):
    parts = line.split(",", 3)
    if len(parts) < 4 or parts[2].strip() != "exec":
        return None
    match = IPC_CALL.match(parts[3])
    return re.sub(r"\s+", " ", match.group(1)) if match else None


def check_binds():
    seen = {}
    actions = {}
    failed = 0
    for conf in sorted((ROOT / "hypr").glob("*.conf")):
        for number, line in enumerate(conf.read_text().splitlines(), 1):
            match = re.match(r"^\s*bind([a-z]*)\s*=\s*([^,]*),\s*([^,]+),", line)
            if not match:
                continue
            flags, mods, key = match.groups()
            combo = normalize_combo(mods, key)
            # Mouse bindings (bindm) live in a separate namespace from key presses.
            namespace = ("mouse" if "m" in flags else "key",) + combo
            where = f"{conf.name}:{number}"
            if namespace in seen:
                print(f"duplicate binding {' + '.join(filter(None, combo))} at {where} and {seen[namespace]}")
                failed += 1
            else:
                seen[namespace] = where
            action = ipc_action(line)
            if action is None:
                continue
            if action in actions:
                print(f"two bindings call the same action '{action}' at {where} and {actions[action]}")
                failed += 1
            else:
                actions[action] = where
    print(f"checked {len(seen)} bindings, {len(actions)} shell actions")
    return failed


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
            if STYLE_ALLOW.search(line):
                continue
            for glyph, name in icons.items():
                if '"%s"' % glyph in line:
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
    """Remove string literals and comments so their words are not matched."""
    text = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`', '""', text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


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


def check_handlers():
    failed = 0
    files = sorted(path for folder in ("shell", "services", "theme") for path in (ROOT / folder).rglob("*.qml"))
    files += sorted(ROOT.glob("*.qml"))
    for path in files:
        for line, handler, name in injected_parameter_uses(path.read_text()):
            print(f"{path.relative_to(ROOT)}:{line}: {handler} uses injected parameter '{name}'; declare it ({handler.split('.')[-1]}: {name} => ...)")
            failed += 1
    print(f"checked signal handlers in {len(files)} QML files")
    return failed


# ---- Hyprland: two dialects and a runtime copy of the same numbers ----------
# hypr/hyprland.conf and hypr/hyprland.lua are the same session written twice,
# and services/hypr/HyprAnimations.js is a third copy of the animation table
# that the shell re-emits when the animation mode changes. Nothing held them
# together: `--verify-config` only says each file parses on its own.
#
# Deliberately narrow. Only the look-and-feel scalars and the animation table
# are compared, because those are what a design change touches in one file and
# forgets in the other. Bindings stay out: checks.py binds covers the conf ones
# and the Lua bind dialect is different enough that a shared parser would be a
# second source of bugs.
HYPR_SECTIONS = ("general", "decoration", "misc", "input", "dwindle")
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


def _hypr_lua(text):
    """The same map, from hl.config / hl.animation / hl.curve."""
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
    config = re.search(r"hl\.config\(\{(.*)\n\}\)", text, re.S)
    if config:
        for section in HYPR_SECTIONS:
            block = re.search(r"\b" + section + r"\s*=\s*\{", config.group(1))
            if not block:
                continue
            body = _lua_block(config.group(1), block.end() - 1)
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


def check_hypr():
    conf = _hypr_conf((ROOT / "hypr" / "hyprland.conf").read_text())
    lua = _hypr_lua((ROOT / "hypr" / "hyprland.lua").read_text())
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

    # The shell's own copy of the animation table, which it re-emits when the
    # animation mode changes. A leaf that drifts here is a mode switch that
    # silently changes the look.
    source = (ROOT / "services" / "hypr" / "HyprAnimations.js").read_text()
    for match in re.finditer(
            r"\{\s*leaf:\s*\"(\w+)\",\s*speed:\s*([-\d.]+),\s*bezier:\s*\"(\w+)\",\s*style:\s*\"([^\"]*)\"(.*?)\}",
            source):
        leaf, speed, bezier, style, tail = match.groups()
        key = "animation:" + leaf
        if key not in conf:
            problems.append(f"{key}: in HyprAnimations.js but not in hyprland.conf")
            continue
        on = "0" if "off: true" in tail else "1"
        parts = [on, _fmt(speed), bezier]
        if style:
            parts.append(style)
        want = ",".join(parts)
        if conf[key] != want:
            problems.append(f"{key}: HyprAnimations.js {want!r} vs hyprland.conf {conf[key]!r}")

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
    if command == "hypr":
        return 1 if check_hypr() else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
