#!/usr/bin/env python3
"""Live microphone level for Settings > Audio.

Runs `pw-record` in raw mode to a pipe (nothing is written to disk) and prints
one JSON line per interval: {"level": 0..1, "peak": 0..1}, both on a dBFS
scale from -60 dB (0) to 0 dB (1). The stream is named
buchhwin-shell-level-meter so the shell can leave it out of "microphone in
use", and it opts out of WirePlumber's stream state so no volume or target is
remembered for it. Stops pw-record when terminated or when stdout closes.

  audio-level.py [--target NODE_NAME] [--interval-ms 50]
"""

import array
import argparse
import ctypes
import json
import math
import signal
import subprocess
import sys

RATE = 16000
FLOOR_DB = -60.0
NODE_NAME = "buchhwin-shell-level-meter"


def measure(data):
    """RMS and peak amplitude of native-endian float32 samples."""
    samples = array.array("f")
    samples.frombytes(data[: len(data) - len(data) % samples.itemsize])
    if not samples:
        return 0.0, 0.0
    total = 0.0
    peak = 0.0
    for value in samples:
        if value != value:  # NaN from a broken source counts as silence
            continue
        magnitude = abs(value)
        total += magnitude * magnitude
        peak = max(peak, magnitude)
    return math.sqrt(total / len(samples)), peak


def to_meter(amplitude, floor_db=FLOOR_DB):
    """Map an amplitude to 0..1 on a dBFS scale (floor_db → 0, 0 dB → 1)."""
    if amplitude <= 0:
        return 0.0
    decibels = 20 * math.log10(amplitude)
    return round(min(1.0, max(0.0, 1 - decibels / floor_db)), 3)


def chunk_bytes(interval_ms, rate=RATE):
    return max(1, rate * interval_ms // 1000) * 4


def record_command(target=None, rate=RATE, interval_ms=50):
    properties = ("{ node.name = \"%s\" application.name = \"buchhwin-shell\" media.name = \"Level meter\""
                  " state.restore-props = false state.restore-target = false }" % NODE_NAME)
    command = ["pw-record", "--raw", "--format", "f32", "--rate", str(rate), "--channels", "1",
               "--latency", "%dms" % interval_ms, "-P", properties]
    if target:
        command += ["--target", target]
    return command + ["-"]


def die_with_parent():
    # PR_SET_PDEATHSIG: pw-record stops even if this helper is killed hard.
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", default="")
    parser.add_argument("--interval-ms", type=int, default=50)
    options = parser.parse_args(argv)
    interval = min(500, max(20, options.interval_ms))
    if options.target and (options.target.startswith("-") or any(char.isspace() for char in options.target)):
        print("invalid target", file=sys.stderr)
        return 2

    process = subprocess.Popen(record_command(options.target, RATE, interval), stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, preexec_fn=die_with_parent)

    def stop(*_):
        process.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    size = chunk_bytes(interval)
    try:
        while True:
            data = process.stdout.read(size)
            if not data:
                break
            rms, peak = measure(data)
            sys.stdout.write(json.dumps({"level": to_meter(rms), "peak": to_meter(peak)}) + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
    return 0 if process.returncode in (0, -signal.SIGTERM) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
