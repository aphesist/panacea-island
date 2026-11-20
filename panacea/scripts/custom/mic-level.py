#!/usr/bin/env python3
"""panacea-local: the microphone's loudness for the island's voice wave (PkVoiceWave).

Prints one number per 50 ms, 0..1: how far the sound is above the room's noise floor (tracked:
it follows quiet moments down at once and creeps up slowly), 0 at the floor + 5 dB, 1 at 27 dB
above it. Silence stays dots, speech fills the bars; no auto-gain (cava's autosens made room
noise look loud).
Runs only while the wave listens; exits when its reader goes away.
"""
import math
import array
import signal
import subprocess
import sys

RATE, CHUNK = 8000, 400          # 50 ms of 16-bit mono
GATE, SPAN = 5.0, 22.0           # dB above the floor: where bars start, how far they grow
RISE = 0.03                       # dB per chunk the floor may creep up (0.6 dB/s: speech never lifts it)

signal.signal(signal.SIGPIPE, signal.SIG_DFL)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))      # so `finally` stops the recorder
# parec writes as it records (pw-record buffers stdout in pipes, seconds late)
rec = subprocess.Popen(["parec", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
                        "--latency-msec=20"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
assert rec.stdout is not None
floor = None
try:
    while True:
        buf = rec.stdout.read(CHUNK * 2)
        if not buf or len(buf) < 2:
            break
        a = array.array("h", buf[: len(buf) // 2 * 2])
        rms = math.sqrt(sum(x * x for x in a) / len(a)) if a else 0.0
        db = 20 * math.log10(rms / 32768) if rms > 0 else -120.0
        if db > -60:                  # the stream fades in from digital silence: not a floor
            floor = db if floor is None else min(db, floor + RISE)
        lvl = 0.0 if floor is None else max(0.0, min(1.0, (db - floor - GATE) / SPAN)) ** 0.7   # lifts quiet speech
        sys.stdout.write(f"{lvl:.3f}\n")
        sys.stdout.flush()
except (BrokenPipeError, KeyboardInterrupt, SystemExit):
    pass
finally:
    rec.terminate()
