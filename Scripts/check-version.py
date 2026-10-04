#!/usr/bin/env python3
"""Check all maintained version values; optionally validate a release tag."""
import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("VERSION must contain a three-part release version")
    manifest = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "Core/Cargo.toml").read_text(), re.M)
    lock = re.search(r'name = "quietspeak-core"\nversion = "([^"]+)"', (ROOT / "Core/Cargo.lock").read_text())
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    values = {
        "Core/Cargo.toml": manifest.group(1) if manifest else None,
        "Core/Cargo.lock": lock.group(1) if lock else None,
        "Resources/Info.plist": info.get("CFBundleShortVersionString"),
    }
    for name, value in values.items():
        if value != version:
            raise SystemExit(f"Version mismatch: {name}={value}, VERSION={version}")
    if args.tag and args.tag != f"v{version}":
        raise SystemExit(f"Tag must be v{version}; got {args.tag}")
    print(f"Version verified: {version}")


if __name__ == "__main__":
    main()
