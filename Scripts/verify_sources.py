#!/usr/bin/env python3
"""Static consistency checks. Runs on any OS (no Xcode / macOS required).

Checks: required files, Info.plist XML, XcodeGen paths, localization key coverage,
JS bridge symbol coverage, signing flags, and absence of any paywall/IAP code.
"""
from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ERRORS: list[str] = []
WARNINGS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def warn(message: str) -> None:
    WARNINGS.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


# 1. required files
required = [
    "project.yml",
    ".gitignore",
    ".github/workflows/build-unsigned-ipa.yml",
    "SWFPlayer/Info.plist",
    "SWFPlayer/Resources/Web/player.html",
    "SWFPlayer/Resources/Web/.gitkeep",
    "SWFPlayer/Resources/Assets.xcassets/Contents.json",
    "SWFPlayer/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "SWFPlayer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "Scripts/fetch-ruffle.sh",
    "Scripts/package-ipa.sh",
    "Scripts/make_icon.py",
    "Scripts/verify_sources.py",
]
for item in required:
    if not (ROOT / item).is_file():
        fail(f"missing required file: {item}")

swift_files = sorted((ROOT / "SWFPlayer" / "Sources").glob("*.swift"))
if len(swift_files) < 6:
    fail("expected at least 6 Swift source files")

# 2. Info.plist is valid XML plist
try:
    with (ROOT / "SWFPlayer" / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("Info.plist CFBundleIdentifier should be $(PRODUCT_BUNDLE_IDENTIFIER)")
    if "zh-Hans" not in info.get("CFBundleLocalizations", []):
        fail("Info.plist CFBundleLocalizations must include zh-Hans")
except Exception as exc:  # noqa: BLE001
    fail(f"Info.plist is not a valid plist: {exc}")

# 3. XcodeGen source paths exist
project_yml = read("project.yml")
for match in re.finditer(r"^\s*-?\s*path:\s*(\S+)\s*$", project_yml, re.MULTILINE):
    path = match.group(1)
    if not (ROOT / path).exists():
        fail(f"project.yml references a missing path: {path}")
if "SWFPlayer/Resources/Web" not in project_yml:
    fail("project.yml must include the Web folder reference")

# 4. localization key coverage across all three languages
localization = read("SWFPlayer/Sources/Localization.swift")
sections: dict[str, set[str]] = {}
current: str | None = None
for line in localization.splitlines():
    marker = re.match(r"\s*\.(en|zhHans|ja):\s*\[", line)
    if marker:
        current = marker.group(1)
        sections[current] = set()
        continue
    if current and re.match(r"\s*\],?\s*$", line):
        current = None
        continue
    if current:
        key = re.match(r'\s*"([A-Za-z0-9_.]+)"\s*:', line)
        if key:
            sections[current].add(key.group(1))

for language in ("en", "zhHans", "ja"):
    if language not in sections:
        fail(f"Localization.swift has no .{language} table")
if len(sections) == 3:
    union = set().union(*sections.values())
    for language, keys in sections.items():
        missing = union - keys
        if missing:
            fail(f"language '{language}' is missing keys: {sorted(missing)}")

used_keys: set[str] = set()
for swift in swift_files:
    if swift.name == "Localization.swift":
        continue
    used_keys.update(re.findall(r'\bL\(\s*"([A-Za-z0-9_.]+)"', swift.read_text(encoding="utf-8")))
all_keys = set().union(*sections.values()) if sections else set()
for key in sorted(used_keys - all_keys):
    fail(f"L(\"{key}\") used in Swift but missing from Localization.swift")

# 5. JS bridge symbols used by Swift must exist in player.html
html = read("SWFPlayer/Resources/Web/player.html")
js_calls: set[str] = set()
for swift in swift_files:
    js_calls.update(re.findall(r"\bSWF\.(\w+)\(", swift.read_text(encoding="utf-8")))
for name in sorted(js_calls):
    if not re.search(r"\b" + re.escape(name) + r"\s*:\s*function", html):
        fail(f"SWF.{name}() is called from Swift but not defined in player.html")
if "swfapp://localhost/Web/" not in html:
    fail("player.html publicPath does not match PlayerURL.publicPath")

swift_all = "\n".join(s.read_text(encoding="utf-8") for s in swift_files)
if 'static let scheme = "swfapp"' not in swift_all:
    fail("PlayerURL.scheme changed without updating player.html publicPath")

# 6. no paywall / IAP / usage counters anywhere
for forbidden in ("import StoreKit", "SKPayment", "SKProduct", "productsRequest",
                  "playCount", "maxFreePlays", "isVIP", "verifyReceipt"):
    if forbidden in swift_all:
        fail(f"forbidden paywall/IAP symbol present: {forbidden}")
if "static let vipLimitEnabled = false" not in swift_all:
    fail("BuildInfo.vipLimitEnabled must remain false")

# 7. workflow produces a genuinely unsigned IPA
workflow = read(".github/workflows/build-unsigned-ipa.yml")
for token in ("runs-on: macos-15", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
              "Scripts/fetch-ruffle.sh", "Scripts/package-ipa.sh", "actions/upload-artifact@v4"):
    if token not in workflow:
        fail(f"workflow is missing: {token}")
if "\t" in workflow or "\t" in project_yml:
    fail("YAML files must not contain tab characters")

# 8. Runtime binaries must never be committed.
# CI downloads them into Web/ just before this check runs, so inspect the git
# index rather than the working tree; otherwise every successful build warns.
tracked: list[str] = []
try:
    result = subprocess.run(
        ["git", "ls-files", "SWFPlayer/Resources/Web"],
        cwd=ROOT, capture_output=True, text=True, check=False
    )
    if result.returncode == 0:
        tracked = result.stdout.splitlines()
except OSError:
    pass
committed_binaries = [p for p in tracked if p.endswith((".wasm", ".js", ".js.map"))]
if committed_binaries:
    warn(f"Runtime binaries are tracked by git and should be ignored: {committed_binaries}")

# report
print(f"Checked {len(swift_files)} Swift files, {len(used_keys)} localization keys, "
      f"{len(js_calls)} JS bridge calls.")
for language, keys in sorted(sections.items()):
    print(f"  language {language:8s}: {len(keys)} keys")
for message in WARNINGS:
    print(f"WARNING: {message}")
for message in ERRORS:
    print(f"ERROR: {message}")

if ERRORS:
    print(f"\nFAILED with {len(ERRORS)} error(s)")
    sys.exit(1)
print("\nAll static checks passed.")
