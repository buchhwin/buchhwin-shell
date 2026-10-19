#!/usr/bin/env python3
"""A button with words puts the forward chevron after them.

ShellButton has `trailingIcon` for a button that goes on somewhere (Next, a
link to another Settings page): in the leading slot the chevron stood before
the words ("› Start", "› Appearance"), which reads as going back. An icon-only
button may still be the chevron alone (next month, move right). This fails on
a ShellButton that has text and `icon: Icons.forward`.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OPEN = re.compile(r"\bShellButton\s*\{")


def blocks(text):
    """(line number, own text) of every ShellButton block: its body with the
    blocks nested in it cut out, so a child's properties are not its own."""
    for match in OPEN.finditer(text):
        depth, i, own = 1, match.end(), []
        while i < len(text) and depth:
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            elif depth == 1:
                own.append(c)
            i += 1
        yield text.count("\n", 0, match.start()) + 1, "".join(own)


def main():
    failures = []
    checked = 0
    for path in sorted((ROOT / "shell").rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        # Comments say "icon: Icons.forward" now and then; only code counts.
        code = "\n".join(re.sub(r"(^|\s)//.*$", "", line) for line in text.splitlines())
        for number, own in blocks(code):
            checked += 1
            if not re.search(r"\bicon:\s*Icons\.forward\b", own):
                continue
            words = re.search(r'\btext:\s*([^;\n]+)', own)
            if words and words.group(1).strip() not in ('""', "''"):
                failures.append("%s:%d: a ShellButton with words and the chevron in front of them - use trailingIcon: Icons.forward"
                                % (path.relative_to(ROOT), number))
    if checked < 50:
        failures.append("only %d ShellButtons found - did the pattern go stale?" % checked)
    for failure in failures:
        print("FAIL", failure)
    if failures:
        print("TESTS FAILED forward_chevron_test")
        return 1
    print("TESTS PASSED forward_chevron_test (%d buttons)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
