#!/usr/bin/env python3
"""The system-wide lid line (install/fingerprint-lid.sh) with the real libpam.

A scratch PAM service directory (pam_start_confdir) runs the exact line printed
by `fingerprint-lid.sh line` with stand-ins: the helper path points to a stub
lid helper, pam_fprintd and pam_unix are pam_exec stand-ins that record that
they ran and succeed or fail. Nothing touches /etc/pam.d, fprintd or real
passwords; this runs as the normal user.
"""
import ctypes
import ctypes.util
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAM_SUCCESS = 0
PAM_AUTH_ERR = 7
PAM_ESTABLISH_CRED = 0x2
failures = []


class PamMessage(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class PamResponse(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_char_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(PamMessage)),
                        ctypes.POINTER(ctypes.POINTER(PamResponse)), ctypes.c_void_p)


class PamConv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


def no_conversation(count, messages, response, data):
    return 19  # PAM_CONV_ERR: the stack under test never asks


def script(path, body):
    path.write_text("#!/bin/sh\n" + body + "\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def check(condition, message):
    if not condition:
        failures.append(message)


def main():
    name = ctypes.util.find_library("pam") or "libpam.so.0"
    try:
        libpam = ctypes.CDLL(name)
        start = libpam.pam_start_confdir
    except (OSError, AttributeError):
        # 77 is the skip status (the autotools convention); scripts/test.sh
        # names it in its summary instead of counting it as a pass.
        print("skipped pam_lid_test (libpam with pam_start_confdir not available)")
        return 77
    start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(PamConv), ctypes.c_char_p,
                      ctypes.POINTER(ctypes.c_void_p)]
    libpam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libpam.pam_setcred.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libpam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
    conversation = PamConv(CONV(no_conversation), None)
    user = os.environ.get("USER") or subprocess.run(["id", "-un"], capture_output=True, text=True).stdout.strip()

    line = subprocess.run([str(ROOT / "install/fingerprint-lid.sh"), "line"], capture_output=True,
                          text=True, check=True).stdout.strip()
    installed_helper = "/usr/local/bin/buchhwin-lid-closed"
    check(line.split()[-1] == installed_helper, "line calls the installed helper")

    with tempfile.TemporaryDirectory(prefix="buchhwin-pamlid.") as tmp:
        tmp = Path(tmp)
        confdir = tmp / "pam.d"
        confdir.mkdir()
        lid = tmp / "lid"
        (lid / "LID").mkdir(parents=True)
        # The real helper with test lid files instead of /proc.
        helper = tmp / "helper"
        script(helper, f'exec "{ROOT}/session/pam/buchhwin-lid-closed" --lid-dir "{lid}" --no-upower')
        fprintd = tmp / "fprintd"
        script(fprintd, f'echo ran >> "{tmp}/fprintd.ran"; exit $(cat "{tmp}/fprintd.result")')
        unix = tmp / "unix"
        script(unix, f'echo ran >> "{tmp}/unix.ran"; exit $(cat "{tmp}/unix.result")')

        def service(helper_path):
            # Shape of the generated system-auth auth section around the line.
            return "\n".join(([line.replace(installed_helper, str(helper_path))] if helper_path else []) + [
                f"auth sufficient pam_exec.so quiet quiet_log {fprintd}",
                f"auth sufficient pam_exec.so quiet quiet_log {unix}",
                "auth required pam_deny.so",
                "account required pam_permit.so",
                "",
            ])

        (confdir / "lid-test").write_text(service(helper))
        (confdir / "lid-missing").write_text(service(tmp / "does-not-exist"))
        (confdir / "baseline").write_text(service(None))

        def authenticate(svc, lid_state, finger_ok, password_ok):
            (lid / "LID" / "state").write_text(f"state:      {lid_state}\n")
            (tmp / "fprintd.result").write_text("0" if finger_ok else "1")
            (tmp / "unix.result").write_text("0" if password_ok else "1")
            for marker in ("fprintd.ran", "unix.ran"):
                (tmp / marker).unlink(missing_ok=True)
            handle = ctypes.c_void_p()
            rc = start(svc.encode(), user.encode(), ctypes.byref(conversation), str(confdir).encode(), ctypes.byref(handle))
            if rc != PAM_SUCCESS:
                failures.append(f"pam_start_confdir failed ({rc})")
                return None
            auth = libpam.pam_authenticate(handle, 0)
            cred = libpam.pam_setcred(handle, PAM_ESTABLISH_CRED) if auth == PAM_SUCCESS else None
            libpam.pam_end(handle, auth)
            return {"auth": auth, "cred": cred, "fprintd": (tmp / "fprintd.ran").exists(),
                    "unix": (tmp / "unix.ran").exists()}

        # pam_setcred: the stand-ins return PAM_IGNORE, so compare with the
        # stack without the line.
        base_finger = authenticate("baseline", "open", True, False)
        base_password = authenticate("baseline", "open", False, True)
        r = authenticate("lid-test", "open", True, False)
        check(r and r["auth"] == PAM_SUCCESS and r["fprintd"] and not r["unix"], f"lid open: finger unlocks as before {r}")
        check(r and r["cred"] == base_finger["cred"], f"lid open: setcred as without the line {r} {base_finger}")
        r = authenticate("lid-test", "open", False, True)
        check(r and r["auth"] == PAM_SUCCESS and r["fprintd"] and r["unix"], f"lid open: reader timeout then password {r}")
        r = authenticate("lid-test", "closed", True, False)
        check(r and r["auth"] == PAM_AUTH_ERR and not r["fprintd"] and r["unix"],
              f"lid closed: reader skipped, a finger cannot unlock, wrong password fails {r}")
        r = authenticate("lid-test", "closed", False, True)
        check(r and r["auth"] == PAM_SUCCESS and not r["fprintd"] and r["unix"], f"lid closed: password unlocks at once {r}")
        check(r and r["cred"] == base_password["cred"], f"lid closed: setcred as without the line {r} {base_password}")
        r = authenticate("lid-test", "closed", False, False)
        check(r and r["auth"] == PAM_AUTH_ERR, f"lid closed: the line never grants access {r}")
        r = authenticate("lid-missing", "closed", True, False)
        check(r and r["auth"] == PAM_SUCCESS and r["fprintd"], f"missing helper: normal stack with the reader {r}")
        r = authenticate("lid-missing", "closed", False, False)
        check(r and r["auth"] == PAM_AUTH_ERR and r["fprintd"] and r["unix"], f"missing helper: wrong password still fails {r}")

    for failure in failures:
        print(f"FAIL pam_lid_test: {failure}")
    if failures:
        print(f"TESTS FAILED pam_lid_test ({len(failures)} failed)")
        return 1
    print("TESTS PASSED pam_lid_test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
