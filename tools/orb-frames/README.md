# orb-frames

Records the boopis bot faces ([orb2](https://github.com/aphesist/orb2), MIT, `orb-avatar.js`) as
vector frames for the island (`OrbStore.qml`, `BotOrb.qml`). orb2 runs in headless Chromium with a
virtual clock; every canvas fill is captured, eyes are clipped to the body, and each body shape is
saved as one JSON (`spin`, a loop per reaction, `<r>>in` / `<r>>out` morphs; 80 body points).

    uv run --with playwright --with shapely --with numpy python record.py OUT [shape ...]
    uv run --with numpy python smooth.py OUT/*.json      # fill orb2's held frames, close loop seams
    tar -C OUT -cf - . | xz -9e > ../../data/orbs.tar.xz

Uses the system Chromium (`/usr/bin/chromium`). All 15 shapes take about 10 minutes.
