#!/usr/bin/env python3
"""Unit test for scripts/audio-level.py with synthetic samples (no PipeWire)."""

import array
import importlib.util
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("level", ROOT / "scripts" / "audio-level.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def samples(values):
    return array.array("f", values).tobytes()


check(module.measure(b"") == (0.0, 0.0), "no data is silence")
check(module.measure(samples([0.0] * 800)) == (0.0, 0.0), "zeros are silence")
rms, peak = module.measure(samples([0.5, -0.5] * 400))
check(abs(rms - 0.5) < 1e-6 and abs(peak - 0.5) < 1e-6, "square wave rms and peak")
sine = [math.sin(2 * math.pi * 440 * index / 16000) for index in range(800)]
rms, peak = module.measure(samples(sine))
check(abs(rms - 1 / math.sqrt(2)) < 0.01 and peak > 0.99, "sine rms is 1/sqrt(2)")
rms, _ = module.measure(samples([1.0, 1.0]) + b"\x00\x01")
check(abs(rms - 1.0) < 1e-6, "partial trailing sample ignored")
rms, peak = module.measure(samples([float("nan"), 0.25]))
check(peak == 0.25, "NaN ignored")

check(module.to_meter(0) == 0.0, "silence is 0")
check(module.to_meter(1.0) == 1.0, "0 dBFS is full")
check(module.to_meter(2.0) == 1.0, "clipping is capped")
check(module.to_meter(0.001) == 0.0, "-60 dBFS is the floor")
check(module.to_meter(0.0001) == 0.0, "below the floor is 0")
check(abs(module.to_meter(0.0316) - 0.5) < 0.01, "-30 dBFS is half")

check(module.chunk_bytes(50) == 3200, "50 ms at 16 kHz float32")
check(module.chunk_bytes(0) == 4, "at least one sample")

command = module.record_command("alsa_input.test", 16000, 50)
check(command[0] == "pw-record" and command[-1] == "-", "records to stdout, never a file")
check("--raw" in command and command[command.index("--target") + 1] == "alsa_input.test", "raw mode with target")
properties = command[command.index("-P") + 1]
check(module.NODE_NAME in properties and "state.restore-props = false" in properties
      and "state.restore-target = false" in properties, "meter stream name and no stored state")
check("--target" not in module.record_command(None), "default source without a target")

if failures:
    for failure in failures:
        print("FAIL audio_level_test:", failure)
    sys.exit(1)
print("audio_level_test passed")
