#!/usr/bin/env python3
"""The shell's words say the same thing the same way everywhere: a button
that asks before it destroys something asks with its verb and a question mark
("Remove?"), a mouse button's click is a "right-click", a key combination in
running text is written as the compact hint (Super+L) the key caps beside it
name, and a time is "5 minutes ago" wherever the shell says how long ago.
Seventeen different armed labels, two key notations and two relative-time
styles had grown apart before this held them."""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
failures = []


def literals(text):
    """(line number, string literal) for every "..." in QML/JS code, comments
    left out."""
    found = []
    line, i, n = 1, 0, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            line += text.count("\n", i, end)
            i = end
            continue
        elif c in "\"'`":
            start, i = i + 1, i + 1
            while i < n and text[i] != c:
                if text[i] == "\\":
                    i += 1
                elif text[i] == "\n":
                    line += 1
                i += 1
            found.append((line, text[start:i]))
        i += 1
    return found


def sources(*roots, suffixes=(".qml",)):
    for root in roots:
        for path in sorted((ROOT / root).rglob("*")):
            if path.suffix in suffixes:
                yield path


CONFIRM = re.compile(r'confirmText:\s*(?:[^"\n]*\?\s*)?"([^"]*)"(?:\s*:\s*"([^"]*)")?')
for path in sources("shell"):
    text = path.read_text()
    relative = path.relative_to(ROOT)
    # A destructive button's second press asks with its verb.
    for number, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        for match in CONFIRM.finditer(line):
            for label in filter(None, match.groups()):
                if not label.endswith("?"):
                    failures.append(f'{relative}:{number}: armed label "{label}" asks without a question mark')
    for number, literal in literals(text):
        # "right-click", "middle-click": one word, as a noun and as a verb.
        if re.search(r"\b(right|middle|left) click", literal, re.IGNORECASE):
            failures.append(f'{relative}:{number}: "{literal[:60]}" writes a click apart (right-click)')
    # A key in a sentence is the compact hint, as in "Super+L locks the screen".
    for number, line in enumerate(text.splitlines(), 1):
        if re.search(r'keyHint\("[^"]+"\)\s*\+\s*"', line) or re.search(r'"\s*\+\s*ShortcutService\.keyHint\("[^"]+"\)', line):
            failures.append(f"{relative}:{number}: a key in running text without the compact hint (keyHint(..., true))")

# ShellButton's own default is a question too.
button = (ROOT / "shell" / "components" / "ShellButton.qml").read_text()
default = re.search(r'property string confirmText:\s*"([^"]*)"', button)
if not default or not default.group(1).endswith("?"):
    failures.append("ShellButton's default armed label asks without a question mark")

# How long ago: "5 minutes ago", never "5 min ago".
for path in sources("services", "shell", suffixes=(".js", ".qml")):
    for number, literal in literals(path.read_text()):
        if re.search(r"\bmin ago\b", literal):
            failures.append(f'{path.relative_to(ROOT)}:{number}: "{literal}" - minutes are written out ("5 minutes ago")')

for failure in failures:
    print("FAIL", failure)
if failures:
    sys.exit(1)
print("wording_test: ok")
