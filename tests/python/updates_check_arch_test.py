#!/usr/bin/env python3
"""scripts/updates-check.sh's two Arch sections: @news (the AUR helper's -Pw,
online checks that worked only) and @pacnew (pacdiff -o). On a PATH of
stand-ins as tests/updates-check-test.sh builds it: no mirror, no AUR, no
archlinux.org and no real pacman database is asked."""

import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "updates-check.sh"
BASH = shutil.which("bash") or "/bin/bash"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def section(output, name):
    """The body of @NAME, or None without one."""
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("@%s " % name):
            body = []
            for following in lines[index + 1:]:
                if following.startswith("@"):
                    break
                body.append(following)
            return line.split(" ", 1)[1], "\n".join(body).strip()
    return None


with tempfile.TemporaryDirectory(prefix="buchhwin-archextras.") as raw:
    sandbox = pathlib.Path(raw)
    bin_dir, calls = sandbox / "bin", sandbox / "calls.log"
    for directory in (bin_dir, sandbox / "home", sandbox / "cache", sandbox / "run"):
        directory.mkdir()
    for tool in ("mktemp", "rm", "timeout", "cat", "tail", "python3", "mkdir", "cp", "sort", "awk", "jq"):
        real = subprocess.run(["bash", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip()
        if real:
            (bin_dir / tool).symlink_to(real)

    def stub(name, body):
        (bin_dir / name).write_text('#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' % (name, calls, body))
        (bin_dir / name).chmod(0o755)

    stub("checkupdates", 'exit "${STUB_EXIT:-2}"')
    stub("pacman", "exit 0")
    stub("flatpak", "exit 0")
    stub("paru", """case "$*" in
  -Pw*) [ -n "$NEWS" ] && printf '%s\\n' "$NEWS" || { echo "no new news" >&2; exit 1; } ;;
  *) exit 1 ;;
esac""")
    stub("pacdiff", '[ "$*" = "-o" ] || exit 2\nprintf "/etc/pacman.conf.pacnew\\n"')
    (sandbox / "os-arch").write_text("ID=arch\n")
    (sandbox / "os-fedora").write_text("ID=fedora\n")
    stub("dnf5", 'case "$*" in check-upgrade*) printf "{\\"upgrades\\": []}\\n" ;; advisory*) printf "[]\\n" ;; esac')
    stub("rpm", "exit 0")

    def run(release, *args, **env):
        calls.write_text("")
        environment = {"PATH": str(bin_dir), "HOME": str(sandbox / "home"), "XDG_CACHE_HOME": str(sandbox / "cache"),
                       "XDG_RUNTIME_DIR": str(sandbox / "run"), "BUCHHWIN_OS_RELEASE": str(sandbox / release)}
        environment.update(env)
        done = subprocess.run([BASH, str(SCRIPT)] + list(args), env=environment, capture_output=True, text=True, timeout=120)
        return done.stdout, calls.read_text(), done.stderr

    out, log, err = run("os-arch", NEWS="2026-10-02 example-package needs a manual step\n    Move the file first.")
    check(section(out, "news") == ("0", "2026-10-02 example-package needs a manual step\n    Move the file first."),
          "the news, as the helper prints it (%s)" % (section(out, "news"),))
    check(section(out, "pacnew") == ("0", "/etc/pacman.conf.pacnew"), "the .pacnew files (%s)" % (section(out, "pacnew"),))
    check("paru -Pw --color=never" in log and "pacdiff -o" in log, "asked as such (%s)" % log)
    check(out.rstrip().endswith("@end 0"), "and the report still ends")
    check(err == "", "nothing on stderr (%s)" % err[:200])

    out, log, _ = run("os-arch")
    # paru says so on stderr, with exit 1 (paru 2.x).
    check(section(out, "news") == ("1", "") and section(out, "news-stderr") == ("1", "no new news"),
          "no news is an answer (%s, %s)" % (section(out, "news"), section(out, "news-stderr")))

    out, log, _ = run("os-arch", "--cache-only")
    check(section(out, "news") is None and "paru -Pw" not in log, "a --cache-only check never asks archlinux.org")
    check(section(out, "pacnew") is not None, "but lists the local .pacnew files")

    out, log, _ = run("os-arch", STUB_EXIT="1")
    check(section(out, "news") is None, "a failed check asks no news either")

    out, log, _ = run("os-fedora")
    check(section(out, "news") is None and section(out, "pacnew") is None and "pacdiff" not in log, "other systems have neither")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED updates_check_arch_test")
    sys.exit(1)
print("TESTS PASSED updates_check_arch_test")
