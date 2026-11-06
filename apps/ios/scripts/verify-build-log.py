#!/usr/bin/env python3
"""Refuse failed or incomplete xtool builds even if the tool exits with status 0."""
import argparse
import re
from pathlib import Path


def completed_bundle(log, started_ns=None):
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", log.read_text(encoding="utf-8", errors="replace"))
    diagnostics = re.compile(
        r"(?im)^.*(?:\bfatal\s+error:|\berror:|\bbuild\s+failed\b|\*\*\s*build\s+failed\s*\*\*).*$"
    )
    if diagnostics.search(text):
        raise ValueError("compiler/build failure reported; xtool status alone is insufficient")
    outcomes = [line.removeprefix("Wrote to ").strip() for line in text.splitlines()
                if line.startswith("Wrote to ")]
    if len(outcomes) != 1:
        raise ValueError("expected exactly one final bundle outcome from this build")
    bundle = Path(outcomes[0])
    if not bundle.is_dir() or bundle.suffix != ".app" or not (bundle / "Info.plist").is_file():
        raise ValueError("reported app bundle is absent or incomplete")
    # Resources can retain old mtimes after incremental compilation. Info.plist is
    # written by the packer for this outcome, so it must belong to the current run.
    if started_ns is not None and (bundle / "Info.plist").stat().st_mtime_ns + 3_000_000_000 < started_ns:
        raise ValueError("reported app bundle predates this build")
    return bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--started-ns", type=int)
    args = parser.parse_args()
    print(completed_bundle(args.log, args.started_ns))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"Build outcome refused: {error}")
