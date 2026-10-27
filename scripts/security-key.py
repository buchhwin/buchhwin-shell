#!/usr/bin/env python3
"""A security key (a YubiKey or another FIDO2 key) for the lock screen.

The lock screen asks a key first once /etc/pam.d/buchhwin-lock-key is in
place (session/pam/buchhwin-lock-key, pam_u2f): its PIN, then a touch. This
helper is what Settings > Lock Screen > Security key runs.

  security-key.py status   -> one JSON object; asks the key nothing
  security-key.py setup    in a terminal: pam-u2f, this key, the PAM file
  security-key.py add      in a terminal: one more key
  security-key.py off      in a terminal: the PAM file goes, the keys stay listed

Registering asks for the key's PIN and a touch, on the terminal (pamu2fcfg).
It makes a new credential for this computer only and leaves everything else
on the key - a Microsoft or Google sign-in - as it is. Root is needed for two
steps, each through sudo on the terminal: installing pam-u2f when it is
missing, and copying or removing the PAM file.
"""

import json
import os
import pathlib
import pwd
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVICE = "/etc/pam.d/buchhwin-lock-key"
SOURCE = ROOT / "session" / "pam" / "buchhwin-lock-key"
# The same in the PAM file: a fixed origin, so a renamed machine keeps its keys.
ORIGIN = "pam://buchhwin-shell"
# Where pam_u2f looks (authfile= in the PAM file, relative to the home
# directory) and pamu2fcfg's lines go.
AUTHFILE = ".config/Yubico/u2f_keys"
MODULE_DIRS = ["/usr/lib/security", "/usr/lib64/security", "/lib/security", "/lib64/security",
               "/usr/lib/x86_64-linux-gnu/security", "/usr/lib/aarch64-linux-gnu/security"]


def say(text=""):
    print(text, flush=True)


def home():
    return pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)


def user():
    return pwd.getpwuid(os.getuid()).pw_name


def module_installed(dirs=None):
    return any(os.path.exists(os.path.join(d, "pam_u2f.so")) for d in (dirs or MODULE_DIRS))


def tool():
    return shutil.which(os.environ.get("BUCHHWIN_PAMU2FCFG", "pamu2fcfg")) or ""


def credentials(text, name):
    """How many keys the mapping file holds for `name`: its line is
    "name:cred1:cred2", each credential "keyhandle,key,type,options"."""
    count = 0
    for line in str(text or "").splitlines():
        fields = line.strip().split(":")
        if fields[0] == name and len(fields) > 1:
            count += len([field for field in fields[1:] if field.strip()])
    return count


def with_credential(text, name, credential):
    """The mapping file with one more credential for `name`: on the user's
    line, or a line of its own. pamu2fcfg -n prints ":credential"."""
    credential = credential.strip().lstrip(":")
    if not credential or "\n" in credential:
        raise ValueError("pamu2fcfg gave no credential")
    lines = [line for line in str(text or "").splitlines() if line.strip()]
    for index, line in enumerate(lines):
        if line.split(":", 1)[0] == name:
            lines[index] = line.rstrip(":") + ":" + credential
            break
    else:
        lines.append(name + ":" + credential)
    return "\n".join(lines) + "\n"


def devices(listing):
    """Names of the FIDO devices `fido2-token -L` lists:
    "/dev/hidraw8: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"."""
    names = []
    for line in str(listing or "").splitlines():
        match = re.match(r"^\S+:.*\((.+)\)\s*$", line.strip())
        if match:
            names.append(match.group(1).strip())
        elif line.strip():
            names.append("Security key")
    return names


def fido2_token(*args):
    """fido2-token's output, or None when it cannot run."""
    command = os.environ.get("BUCHHWIN_FIDO2_TOKEN", "fido2-token")
    try:
        result = subprocess.run([command] + list(args), capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else ""


def devices_now():
    listing = fido2_token("-L")
    return None if listing is None else devices(listing)


def pin_state(info):
    """Whether a key has a PIN and how many tries it has left, from
    `fido2-token -I` (asks the key nothing that needs the PIN):
    "options: rk, up, noplat, clientPin, ..." and "pin retries: 8"."""
    state = {"set": None, "retries": None}
    for line in str(info or "").splitlines():
        key, _, value = line.partition(":")
        key = key.strip().lower()
        if key == "options":
            options = [option.strip() for option in value.split(",")]
            state["set"] = True if "clientPin" in options else False if "noclientPin" in options else None
        elif key == "pin retries" and value.strip().isdigit():
            state["retries"] = int(value.strip())
    return state


def pins_now(listing):
    """pin_state of every key a `fido2-token -L` listing names, from the same
    lines and in the same order as devices()."""
    paths = [line.strip().split(":", 1)[0] for line in str(listing or "").splitlines() if line.strip()]
    return [pin_state(fido2_token("-I", path)) for path in paths]


def family(os_release=None):
    """arch, fedora or suse from os-release (ID and ID_LIKE), else ""."""
    path = os_release or os.environ.get("BUCHHWIN_OS_RELEASE", "/etc/os-release")
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError:
        return ""
    ids = []
    for line in text.splitlines():
        key, _, value = line.partition("=")
        if key in ("ID", "ID_LIKE"):
            ids += value.strip().strip('"').lower().split()
    for name, words in (("arch", ("arch",)), ("fedora", ("fedora", "rhel")), ("suse", ("suse", "opensuse"))):
        if any(word in ids or any(i.startswith(word) for i in ids) for word in words):
            return name
    return ""


def install_command(name):
    """The packages that bring pam_u2f.so and pamu2fcfg, per distribution."""
    return {"arch": ["sudo", "pacman", "-S", "--needed", "pam-u2f"],
            "fedora": ["sudo", "dnf", "install", "pam-u2f", "pamu2fcfg"],
            "suse": ["sudo", "zypper", "install", "pam_u2f"]}.get(name, [])


def service_text():
    try:
        return pathlib.Path(SERVICE).read_text(encoding="utf-8")
    except OSError:
        return None


def status():
    try:
        mapping = (home() / AUTHFILE).read_text(encoding="utf-8")
    except OSError:
        mapping = ""
    installed = service_text()
    # One listing for both the names and the PINs.
    listing = fido2_token("-L")
    found = None if listing is None else devices(listing)
    return {"ok": True, "module": module_installed(), "tool": bool(tool()),
            "service": installed is not None and "pam_u2f.so" in installed,
            "serviceCurrent": installed is not None and installed == SOURCE.read_text(encoding="utf-8"),
            "keys": credentials(mapping, user()), "devices": found or [], "fido2Token": found is not None,
            "pins": pins_now(listing) if found else []}


def write_mapping(text):
    """The mapping file as pam_u2f wants it: the user's own, 600 in a 700
    directory, written whole or not at all."""
    path = home() / AUTHFILE
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    handle, temp = tempfile.mkstemp(dir=path.parent, prefix=".u2f_keys.")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(text)
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    except BaseException:
        os.unlink(temp)
        raise


def register():
    """One more key in the mapping file; pamu2fcfg asks for the PIN and the
    touch on the terminal (its stderr and /dev/tty), the credential comes on
    its stdout."""
    found = devices_now()
    while not found:
        input("Plug in the security key, then press Enter (Ctrl+C stops): ")
        found = devices_now()
    say("Key: " + ", ".join(found))
    say("Enter the key's PIN when asked, then touch the key when it blinks.")
    say("This adds a sign-in for this computer only; everything else on the key stays as it is.")
    result = subprocess.run([tool(), "-N", "-n", "-o", ORIGIN, "-i", ORIGIN, "-u", user()],
                            stdout=subprocess.PIPE, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        say("The key was not registered (pamu2fcfg ended with %d)." % result.returncode)
        return False
    path = home() / AUTHFILE
    try:
        old = path.read_text(encoding="utf-8")
    except OSError:
        old = ""
    new = with_credential(old, user(), result.stdout)
    write_mapping(new)
    say("Registered: %d key(s) for %s." % (credentials(new, user()), user()))
    return True


def install_service():
    if service_text() == SOURCE.read_text(encoding="utf-8"):
        return True
    say("The lock screen's PAM file goes to %s (sudo):" % SERVICE)
    return subprocess.run(["sudo", "install", "-m", "644", "-o", "root", "-g", "root", str(SOURCE), SERVICE]).returncode == 0


def command_setup(adding):
    say("Security key for the lock screen")
    say()
    if not module_installed() or not tool():
        command = install_command(family())
        if not command:
            say("Install pam-u2f (pam_u2f.so and pamu2fcfg) with the package manager, then run this again.")
            return 1
        say("pam-u2f is missing: " + " ".join(command))
        if subprocess.run(command).returncode != 0 or not module_installed() or not tool():
            say("pam-u2f could not be installed.")
            return 1
    try:
        mapping = (home() / AUTHFILE).read_text(encoding="utf-8")
    except OSError:
        mapping = ""
    if adding or credentials(mapping, user()) == 0:
        if not register():
            return 1
    else:
        say("A key is registered already (%d); Add another key registers one more." % credentials(mapping, user()))
    if not install_service():
        say("The PAM file was not installed.")
        return 1
    say()
    say("Done. Lock the screen to try it: the key's PIN, then a touch.")
    say("The password works as before, and the fingerprint comes after the key.")
    return 0


def command_off():
    if service_text() is None:
        say("The lock screen does not ask for a security key.")
        return 0
    say("Removing %s (sudo):" % SERVICE)
    if subprocess.run(["sudo", "rm", "-f", SERVICE]).returncode != 0:
        say("It was not removed.")
        return 1
    say("The lock screen no longer asks for the key. The registered keys stay in ~/%s;" % AUTHFILE)
    say("setting it up again uses them.")
    return 0


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    command = args[0] if args else ""
    if command == "status":
        print(json.dumps(status()))
        return 0
    try:
        if command in ("setup", "add"):
            return command_setup(command == "add")
        if command == "off":
            return command_off()
    except KeyboardInterrupt:
        say()
        say("Stopped.")
        return 130
    print("usage: security-key.py status | setup | add | off", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
