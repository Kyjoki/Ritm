#!/usr/bin/env python3
"""Create tiny synthetic arm64 app/appex binaries for an offline ad-hoc test."""
import json
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
bundle = Path.home() / ".swiftpm/swift-sdks/darwin.artifactbundle"
sdk = json.loads((bundle / "swift-sdk.json").read_text())["targetTriples"]["arm64-apple-ios"]
sdk_root = bundle / sdk["sdkRootPath"]
linker = bundle / "toolset/bin/ld64.lld"
clang = shutil.which("clang")
if not clang or not linker.is_file():
    raise SystemExit("Swiftly clang and Darwin SDK ld64.lld are required")
source = root / "main.c"
source.write_text("int main(void) { return 0; }\n")
obj = root / "main.o"
binary = root / "tiny-arm64"
subprocess.run([clang, "-target", "arm64-apple-ios17.0", "-fno-stack-protector",
                "-ffreestanding", "-c", str(source), "-o", str(obj)], check=True)
subprocess.run([str(linker), "-arch", "arm64", "-platform_version", "ios", "17.0", "27.1",
                "-e", "_main", "-syslibroot", str(sdk_root), "-lSystem", str(obj),
                "-o", str(binary)], check=True)
app = root / "Fixture.app"
extension = app / "PlugIns/FixtureWidget.appex"
for directory, executable, identifier in [
    (app, "Fixture", "app.ritm.signfixture"),
    (extension, "FixtureWidget", "app.ritm.signfixture.Widget"),
]:
    directory.mkdir(parents=True, exist_ok=True)
    info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
            "CFBundlePackageType": "APPL" if directory == app else "XPC!",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "CFBundleName": executable, "MinimumOSVersion": "17.0"}
    if directory == extension:
        info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
    (directory / "Info.plist").write_bytes(plistlib.dumps(info))
    shutil.copyfile(binary, directory / executable)
    (directory / executable).chmod(0o755)
(root / "Fixture.app-copy").mkdir(exist_ok=True)
for name, identifier, health in [
    ("root", "app.ritm.signfixture", True),
    ("extension", "app.ritm.signfixture.Widget", False),
]:
    entitlements = {"application-identifier": "RITMFIXTUR." + identifier,
                    "com.apple.developer.team-identifier": "RITMFIXTUR",
                    "keychain-access-groups": ["RITMFIXTUR." + identifier],
                    "com.apple.security.application-groups": ["group.app.ritm.signfixture"]}
    if health:
        entitlements["com.apple.developer.healthkit"] = True
    (root / (name + ".entitlements")).write_bytes(plistlib.dumps(entitlements))
(root / "ritm-adhoc-fixture.json").write_text(json.dumps({
    "kind": "synthetic-offline-ad-hoc", "developerCredentials": False, "deviceUsed": False,
}) + "\n")
print(app)
