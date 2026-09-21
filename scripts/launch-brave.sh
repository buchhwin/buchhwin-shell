#!/usr/bin/env bash
set -euo pipefail

# Which password store Chromium uses. `kwallet6`, and the alternative was tried
# and taken back rather than left as a suggestion.
#
# What is measured, so nobody has to guess it again:
#
#   - PAM unlocks **ksecretd**, not kwalletd6. On this Fedora `pam-kwallet`
#     ships a `pam_kwallet5.so` that execs /usr/bin/ksecretd and nothing else;
#     ksecretd owns `org.freedesktop.secrets` and its `kdewallet` collection
#     reports `Locked = false` after login. `kwalletd6` is a separate daemon
#     with its own lock that nothing unlocks, D-Bus activated by whoever asks
#     for `org.kde.kwalletd6`.
#   - So `kwallet6` is why the wallet asks for a password once per login. That
#     is a real cost and it is the one being paid here.
#   - `gnome-libsecret` removes the prompt - it routes to ksecretd, which PAM
#     already opened. It also **separates Brave from its own secrets**:
#     Chromium encrypts its store with a key held by whichever backend it was
#     using, and it cannot move that key between backends. Switching broke
#     sync and the saved passwords with it, which is why this is back.
#
# If the prompt matters more than the sync one day, `gnome-libsecret` is the
# one line to change - and the price is signing in to Brave sync again, with
# the saved passwords coming back from the sync account rather than from disk.
exec brave-browser --password-store=kwallet6 "$@"
