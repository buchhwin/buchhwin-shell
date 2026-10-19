#!/usr/bin/env python3
"""An empty state inside a settings card is a row.

EmptyState has two forms and says which goes where: a row (an icon beside the
text) for a card inside a page, the centred column for an empty panel. Every
EmptyState on a settings page sits inside a card, and both forms were in use
there - one card a centred column with a large icon, the next a row, on the
same page. This reads every settings page and fails on an EmptyState block
that does not say `row: true`.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PAGES = ROOT / "shell" / "settings" / "pages"
START = re.compile(r"\bEmptyState\s*\{")


def blocks(text):
    """Each EmptyState { ... } block with the line it starts on."""
    for match in START.finditer(text):
        depth = 0
        for index in range(match.end() - 1, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    yield text.count("\n", 0, match.start()) + 1, text[match.start():index + 1]
                    break


def main():
    failures = []
    checked = 0
    for path in sorted(PAGES.glob("*.qml")):
        for line, block in blocks(path.read_text(encoding="utf-8")):
            checked += 1
            if not re.search(r"(^|[\s;{])row:\s*true\b", block):
                failures.append("%s:%d" % (path.relative_to(ROOT), line))
    if checked == 0:
        failures.append("no EmptyState found on the settings pages - did the pattern go stale?")
    if failures:
        for failure in failures:
            print("FAIL EmptyState in a settings card without row: true:", failure)
        print("TESTS FAILED settings_empty_state_test")
        return 1
    print("TESTS PASSED settings_empty_state_test (%d empty states)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
