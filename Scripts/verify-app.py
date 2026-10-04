#!/usr/bin/env python3
"""Verify signing, bundle metadata, architecture and system-only dylib links."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--arch", choices=["arm64", "x86_64"])
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = (ROOT / "VERSION").read_text().strip()
    if info.get("CFBundleShortVersionString") != version:
        raise SystemExit("App version differs from source VERSION")
    if info.get("LSMinimumSystemVersion") != "14.0" or not info.get("NSMicrophoneUsageDescription"):
        raise SystemExit("Missing deployment or microphone metadata")
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    arches = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip().split()
    if args.arch and arches != [args.arch]:
        raise SystemExit(f"Unexpected architecture: {arches}")
    links = subprocess.check_output(["otool", "-L", str(binary)], text=True)
    for line in links.splitlines()[1:]:
        dependency = line.strip().split(" (", 1)[0]
        if dependency and not dependency.startswith(("/System/Library/", "/usr/lib/")):
            raise SystemExit(f"External runtime dependency: {dependency}")
    commands = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    deployment = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \d+\s+minos (\S+)", commands)
    if not deployment or deployment.group(1) != "14.0":
        raise SystemExit("Executable deployment target must be macOS 14.0")
    for name in ["LICENSE", "THIRD_PARTY_NOTICES.txt", "AppIcon.icns"]:
        if not (app / "Contents/Resources" / name).is_file():
            raise SystemExit(f"Missing bundled resource: {name}")
    print(f"Verified QuietSpeak {version}: {', '.join(arches)}, signed, macOS 14+, system dylibs only")


if __name__ == "__main__":
    main()
