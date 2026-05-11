#!/usr/bin/env python3
"""Replay canonical SKYSHIELD alert packets over time."""

import argparse
import json
import sys
import time
from pathlib import Path


def load_session(path):
    with path.open("r", encoding="utf-8") as handle:
        session = json.load(handle)

    if not isinstance(session, list):
        raise ValueError("session file must contain a JSON array")

    return sorted(session, key=lambda entry: float(entry["offset"]))


def replay(session):
    previous_offset = 0.0

    for entry in session:
        offset = float(entry["offset"])
        packet = entry["packet"]

        delay = offset - previous_offset
        if delay > 0:
            time.sleep(delay)

        print("[{:.1f}s]".format(offset))
        print(json.dumps(packet, separators=(",", ":")))
        print()
        sys.stdout.flush()

        previous_offset = offset


def main():
    parser = argparse.ArgumentParser(description="Replay SKYSHIELD alert packets to stdout.")
    parser.add_argument(
        "session",
        nargs="?",
        default=str(Path(__file__).with_name("sample-session.json")),
        help="Path to a replay session JSON file.",
    )
    args = parser.parse_args()

    replay(load_session(Path(args.session)))


if __name__ == "__main__":
    main()
