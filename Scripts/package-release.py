#!/usr/bin/env python3
"""Package a verified app, portable source archive and SHA-256 checksums."""
import argparse
import hashlib
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {
    "README.md", "README.en.md", "LICENSE", "VERSION", "rust-toolchain.toml",
    "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md",
    "THIRD_PARTY_NOTICES.txt", ".gitignore", ".gitattributes",
    ".editorconfig", ".swift-format", "build.sh", "test.sh", "check.sh",
}
SOURCE_DIRS = {"Native", "Core", "Vendor", "Resources", "Scripts", "Tests", "Docs", ".github"}


def package_dmg(app, destination, version, arch):
    """Create a drag-to-Applications disk image and verify its mounted app."""
    with tempfile.TemporaryDirectory(prefix="quietspeak-dmg-") as temporary:
        staging = Path(temporary) / "contents"
        staging.mkdir()
        subprocess.run(["ditto", str(app), str(staging / "QuietSpeak.app")], check=True)
        (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
        subprocess.run([
            "hdiutil", "create", "-volname", f"QuietSpeak {version}",
            "-srcfolder", str(staging), "-fs", "HFS+", "-format", "UDZO",
            "-ov", str(destination),
        ], check=True)
        subprocess.run(["hdiutil", "verify", str(destination)], check=True)
        mount = Path(temporary) / "mounted"
        mount.mkdir()
        subprocess.run([
            "hdiutil", "attach", str(destination), "-readonly", "-nobrowse",
            "-mountpoint", str(mount),
        ], check=True)
        try:
            if not (mount / "Applications").is_symlink() or (mount / "Applications").readlink() != Path("/Applications"):
                raise SystemExit("Disk image is missing the Applications shortcut")
            subprocess.run([
                "python3", str(ROOT / "Scripts/verify-app.py"),
                str(mount / "QuietSpeak.app"), "--arch", arch,
            ], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "dist/QuietSpeak.app")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist/releases")
    parser.add_argument("--skip-source", action="store_true", help="Only package the app; used by the second CI architecture")
    args = parser.parse_args()
    app = args.app.resolve()
    subprocess.run(["python3", str(ROOT / "Scripts/check-version.py")], check=True)
    subprocess.run(["python3", str(ROOT / "Scripts/verify-app.py"), str(app)], check=True)
    binary = app / "Contents/MacOS/QuietSpeak"
    arch = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
    if arch not in {"arm64", "x86_64"}:
        raise SystemExit(f"Unsupported release architecture: {arch}")
    version = (ROOT / "VERSION").read_text().strip()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app_dmg = output / f"QuietSpeak-{version}-macOS-{arch}.dmg"
    package_dmg(app, app_dmg, version, arch)
    source_zip = output / f"QuietSpeak-{version}-source.zip"
    outputs = [app_dmg]
    if not args.skip_source:
        with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(ROOT.rglob("*")):
                relative = path.relative_to(ROOT)
                if relative.parts[0] not in SOURCE_DIRS and str(relative) not in ROOT_FILES:
                    continue
                if not path.is_file() or any(part in {".git", "target", "__pycache__", ".DS_Store"} for part in relative.parts):
                    continue
                info = zipfile.ZipInfo(str(Path("QuietSpeak") / relative), date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                info.external_attr = (0o100000 | mode) << 16
                archive.writestr(info, path.read_bytes())
        outputs.append(source_zip)
        with zipfile.ZipFile(source_zip) as archive:
            if archive.testzip():
                raise SystemExit(f"Corrupt archive: {source_zip}")
    checksum = output / f"SHA256SUMS-{arch}.txt"
    checksum.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in outputs))
    print(f"Release files: {output}")


if __name__ == "__main__":
    main()
