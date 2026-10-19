#!/usr/bin/env python3
"""Settings' search finds a page by the words of its own sections and rows.

The search (SettingsNavLogic.matches) looks for every word of the query in a
page's title, subtitle, keywords and group title - it never sees the page
itself, so a section or a row added to a page is found only once its words
are in the page's keywords as well. Typing "night light", "refresh rate",
"natural scrolling" or "time format" said "No settings match" while each was
a row on a page. This reads every settings page, takes each SettingsSection
`title:` and SettingRow `label:` that is a plain string, and fails when one
of its words is not in that page's haystack, so the keywords follow the pages.
A section kept in a file of its own beside the pages (AssistantSection on
Desktop extras, CommandWidgetsSection on Widgets) is read as part of every
page that places it.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
NAV = ROOT / "services" / "settings" / "SettingsNavLogic.js"
PAGES = ROOT / "shell" / "settings" / "pages"

# Words that carry no meaning of their own in a label, and the verbs nearly
# every row could start with ("Show", "Use", "Open"). Anything else a label
# says is a word somebody may type.
FILLER = set("""
a an the of to and or in on for with at by is are be it its this that these your you as from
what when which how all no not yet there one each every own than then up down off out into
my other new again back next before after while about behind under between more
show shows use uses open opens choose run set apply need needs
""".split())

STRING = r'"((?:[^"\\]|\\.)*)"'
FIELD = re.compile(r'(\w+):\s*' + STRING)
ELEMENT = re.compile(r'^(\s*)([A-Z]\w*)\s*\{')
PROPERTY = re.compile(r'^(\s*)(title|label):\s*' + STRING + r'\s*$')
WANTED = {"title": "SettingsSection", "label": "SettingRow"}


def unescape(text):
    """A JavaScript or QML string literal's escapes: \\u{1F600}, \\u201C, \\" and the like."""
    def one(match):
        code = match.group(1) or match.group(2)
        return chr(int(code, 16)) if code else match.group(3)
    return re.sub(r"\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})|\\(.)", one, text)


def nav_pages(source):
    """Each page entry of PAGES with its group title, as the search sees it."""
    pages = {}
    block = source[source.index("const PAGES"):source.index("const GROUPS")]
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("{ id:"):
            continue
        fields = {key: unescape(value) for key, value in FIELD.findall(line)}
        pages[fields["id"]] = fields
    groups = source[source.index("const GROUPS"):]
    for title, ids in re.findall(r'title: "([^"]+)", pages: \[([^\]]*)\]', groups):
        for page_id in re.findall(r'"(\w+)"', ids):
            pages[page_id]["group"] = title
    return pages


def haystack(page):
    return " ".join(page.get(key, "") for key in ("title", "subtitle", "keywords", "group")).lower()


def labels(path):
    """The plain-string section titles and row labels of a page file, each
    with its line number. The element a property belongs to is the nearest
    one opened above it at a smaller indent."""
    found = []
    stack = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        opened = ELEMENT.match(line)
        if opened:
            indent = len(opened.group(1))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack.append((indent, opened.group(2)))
            continue
        assigned = PROPERTY.match(line)
        if not assigned:
            continue
        indent = len(assigned.group(1))
        owner = next((name for depth, name in reversed(stack) if depth < indent), "")
        if owner == WANTED[assigned.group(2)]:
            found.append((number, unescape(assigned.group(3))))
    return found


def sections(path):
    """The files of their own a page places (`AssistantSection {`): QML
    files beside the pages that are not pages themselves."""
    found = []
    for name in re.findall(r"^\s*([A-Z]\w*)\s*\{", path.read_text(encoding="utf-8"), re.M):
        part = PAGES / (name + ".qml")
        if not name.endswith("Page") and part.exists() and part not in found:
            found.append(part)
    return found


def words(label):
    return [word for word in re.findall(r"[0-9a-zäöüß][0-9a-zäöüß+-]*", label.lower())
            if word not in FILLER and len(word) > 1]


def main():
    pages = nav_pages(NAV.read_text(encoding="utf-8"))
    failures = []
    checked = 0
    for page_id, page in sorted(pages.items()):
        path = PAGES / (page_id[0].upper() + page_id[1:] + "Page.qml")
        if not path.exists():
            failures.append("%s: no page file %s" % (page_id, path.relative_to(ROOT)))
            continue
        hay = haystack(page)
        for part in [path] + sections(path):
            for number, label in labels(part):
                checked += 1
                missing = [word for word in words(label) if word not in hay]
                if missing:
                    failures.append("%s:%d: \"%s\" - not in the %s page's keywords: %s"
                                    % (part.relative_to(ROOT), number, label, page_id, " ".join(missing)))
    if checked < 100:
        failures.append("only %d labels found on the settings pages - did the pattern go stale?" % checked)
    if failures:
        for failure in failures:
            print("FAIL", failure)
        print("TESTS FAILED settings_nav_test (%d of %d labels)" % (len(failures), checked))
        return 1
    print("TESTS PASSED settings_nav_test (%d labels on %d pages)" % (checked, len(pages)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
