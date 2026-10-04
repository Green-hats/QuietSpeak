#!/usr/bin/env python3
"""Generate portable dependency inventory and complete notices from locked sources."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def license_files(package):
    directory = Path(package["manifest_path"]).parent
    explicit = package.get("license_file")
    if explicit:
        path = Path(explicit)
        if not path.is_absolute():
            path = directory / path
        return [("package:" + path.name, path, None)]
    # Cargo workspace members often inherit the licenses from their parent.
    while True:
        files = sorted(path for path in directory.iterdir() if path.is_file()
                       and path.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")))
        if files:
            return [(str(path.relative_to(ROOT)) if path.is_relative_to(ROOT)
                     else "package:" + path.name, path, None) for path in files]
        if package.get("source") or directory == ROOT or directory.parent == directory:
            break
        directory = directory.parent
    index_path = ROOT / "Docs/third-party-licenses/index.json"
    index = json.loads(index_path.read_text())
    key = package["name"] + "@" + package["version"]
    entries = index.get(key, [])
    result = []
    for entry in entries:
        path = ROOT / entry["path"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise SystemExit(f"License checksum differs: {path.name}")
        result.append((entry["path"], path, entry["url"]))
    if not result:
        raise SystemExit(f"No license text for {key}; add pinned upstream texts and provenance")
    return result


def main():
    packages = {}
    for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"]:
        command = ["cargo", "metadata", "--manifest-path", str(ROOT / "Core/Cargo.toml"),
                   "--locked", "--format-version", "1", "--filter-platform", target]
        metadata = json.loads(subprocess.check_output(command, text=True))
        for package in metadata["packages"]:
            packages[(package["name"], package["version"], package.get("source"))] = package
    version = (ROOT / "VERSION").read_text().strip()
    sections = [
        f"QuietSpeak {version} — third-party notices\n",
        "QuietSpeak project code is MIT licensed; see the bundled LICENSE.\n"
        "Third-party code keeps its original licenses below. This inventory includes\n"
        "locked macOS, build and development dependencies; it is not a list\n"
        "of libraries all linked into a particular macOS executable.\n\n"
        "TeamSpeak is a trademark of TeamSpeak Systems GmbH. QuietSpeak is an\n"
        "independent client and is not an official TeamSpeak product.\n\n"
        "Vendored sources and patches are documented in Vendor/README.md and\n"
        "Vendor/PROVENANCE.json. Apple system frameworks are provided by macOS.\n",
    ]
    inventory = []
    for package in sorted(packages.values(), key=lambda p: (p["name"], p["version"])):
        if package["name"] == "quietspeak-core":
            continue
        files = license_files(package)
        record = {key: package.get(key) for key in ["name", "version", "license", "repository", "source"]}
        record["license_texts"] = [label for label, _, _ in files]
        record["upstream_license_urls"] = [url for _, _, url in files if url]
        inventory.append(record)
        for label, path, _ in files:
            sections.append(f"\n===== {package['name']} {package['version']} / {label} =====\n\n")
            sections.append(path.read_text(encoding="utf-8").rstrip() + "\n")
    for relative in ["Vendor/audiopus_sys/opus/COPYING",
                     "Vendor/audiopus_sys/opus/LICENSE_PLEASE_READ.txt",
                     "Vendor/tsclientlib/utils/tsproto-structs/declarations/LICENSE-MIT",
                     "Vendor/tsclientlib/utils/tsproto-structs/declarations/LICENSE-APACHE"]:
        sections.append(f"\n===== Bundled source / {relative} =====\n\n")
        sections.append((ROOT / relative).read_text().rstrip() + "\n")
    (ROOT / "THIRD_PARTY_NOTICES.txt").write_text("".join(sections), encoding="utf-8")
    document = {"schema": 1, "project_version": version,
                "scope": "Locked macOS dependency packages including build and development dependencies",
                "packages": inventory}
    (ROOT / "Docs/DEPENDENCIES.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    print(f"Generated notices and inventory for {len(inventory)} locked dependencies")


if __name__ == "__main__":
    main()
