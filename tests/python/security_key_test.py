#!/usr/bin/env python3
"""Unit test for scripts/security-key.py: the mapping file pam_u2f reads, the
devices fido2-token lists, the distribution's packages - with invented
credentials, no key and no sudo."""

import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("security_key", ROOT / "scripts" / "security-key.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


ONE = "KH1,PK1,es256,+presence+pin"
TWO = "KH2,PK2,es256,+presence+pin"

# ---- the mapping file ("user:cred1:cred2") -----------------------------------
check(module.credentials("", "someone") == 0, "no file, no key")
check(module.credentials("someone:" + ONE + "\n", "someone") == 1, "one key")
check(module.credentials("other:" + ONE + "\nsomeone:" + ONE + ":" + TWO + "\n", "someone") == 2,
      "two keys on the user's line, another user's not counted")
check(module.credentials("someone_else:" + ONE + "\n", "someone") == 0, "a name that only begins the same is another user")

first = module.with_credential("", "someone", ":" + ONE + "\n")
check(first == "someone:" + ONE + "\n", "the first key makes the user's line: %r" % first)
second = module.with_credential("other:" + TWO + "\n" + first, "someone", ":" + TWO)
check(second == "other:" + TWO + "\nsomeone:" + ONE + ":" + TWO + "\n", "the next goes on the same line: %r" % second)
check(module.credentials(second, "someone") == 2, "and counts")
for bad in ("", ":", "\n", "KH,PK\nevil:KH,PK"):
    try:
        module.with_credential("", "someone", bad)
        check(False, "%r is refused" % bad)
    except ValueError:
        pass

# ---- fido2-token -L ----------------------------------------------------------
listing = ("/dev/hidraw8: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)\n"
           "/dev/hidraw3: vendor=0x20a0, product=0x42b1 (Nitrokey 3)\n")
check(module.devices(listing) == ["Yubico YubiKey OTP+FIDO+CCID", "Nitrokey 3"], "device names: %s" % module.devices(listing))
check(module.devices("") == [], "no device")
check(module.devices("/dev/hidraw1: vendor=0x1, product=0x2\n") == ["Security key"], "a device without a name")

# ---- the distribution ----------------------------------------------------------
with tempfile.TemporaryDirectory() as tmp:
    def os_release(text):
        path = pathlib.Path(tmp) / "os-release"
        path.write_text(text)
        return module.family(str(path))
    check(os_release('ID=arch\n') == "arch", "Arch")
    check(os_release('ID=cachyos\nID_LIKE=arch\n') == "arch", "an Arch derivative")
    check(os_release('ID=fedora\n') == "fedora", "Fedora")
    check(os_release('ID="opensuse-leap"\nID_LIKE="suse opensuse"\n') == "suse", "openSUSE")
    check(os_release('ID=debian\n') == "", "nothing known")
    check(module.family(str(pathlib.Path(tmp) / "missing")) == "", "no os-release")
check(module.install_command("arch") == ["sudo", "pacman", "-S", "--needed", "pam-u2f"], "pacman's package")
check("pamu2fcfg" in module.install_command("fedora"), "Fedora packages the tool on its own")
check(module.install_command("") == [], "no command without a distribution")
check(module.module_installed([tempfile.gettempdir() + "/no-such-dir"]) is False, "no module in an empty place")

# ---- the PAM file and the helper agree -----------------------------------------
pam = module.SOURCE.read_text()
check("origin=" + module.ORIGIN in pam and "appid=" + module.ORIGIN in pam, "the PAM file has the helper's origin")
check("authfile=" + module.AUTHFILE in pam, "and reads the file the helper writes")
check("pinverification=1" in pam and "pam_deny.so" in pam, "the PIN is asked, and nothing else lets one in")
check("sufficient  pam_u2f.so" in pam.replace("\t", "  "), "a key is enough on its own")

# ---- the commands --------------------------------------------------------------
out, err = io.StringIO(), io.StringIO()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
    code = module.main(["nonsense"])
check(code == 2 and "usage" in err.getvalue(), "an unknown command says how to call it")
module.devices_now = lambda: ["Test key"]
out = io.StringIO()
with contextlib.redirect_stdout(out):
    code = module.main(["status"])
answer = json.loads(out.getvalue())
check(code == 0 and answer["ok"] and answer["devices"] == ["Test key"], "status is one JSON object: %s" % answer)
check(set(answer) == {"ok", "module", "tool", "service", "serviceCurrent", "keys", "devices", "fido2Token"},
      "with the fields the shell reads")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED security_key_test")
    sys.exit(1)
print("TESTS PASSED security_key_test")
