#!/usr/bin/env python3
"""Inspect Ritm's app/appex, code, metadata and optional provisioning structurally.

Does not connect to a phone, authenticate, read signing keys or alter the bundle.
Passing this check is not proof of iOS installation, execution or signature trust.
"""
import argparse
import datetime as dt
import json
import plistlib
import re
import struct
import subprocess
import zipfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


class BundleFiles:
    def __init__(self, path):
        self.path = path.resolve()
        self.zip = zipfile.ZipFile(path) if path.is_file() else None
        if self.zip:
            require(self.zip.testzip() is None, "IPA ZIP integrity failure")
            roots = [x[:-10] for x in self.zip.namelist()
                     if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", x)]
            require(len(roots) == 1, "IPA must contain exactly one Payload app")
            self.prefix = roots[0]
        else:
            require(path.is_dir() and path.suffix == ".app", "expected an .app directory or IPA")
            self.prefix = ""

    def names(self):
        if self.zip:
            return [n[len(self.prefix):] for n in self.zip.namelist() if n.startswith(self.prefix)]
        return [str(p.relative_to(self.path)).replace("\\", "/") for p in self.path.rglob("*") if p.is_file()]

    def read(self, name):
        if self.zip:
            return self.zip.read(self.prefix + name)
        return (self.path / name).read_bytes()


def macho(data):
    require(data[:4] == b"\xcf\xfa\xed\xfe", "expected an arm64 Mach-O binary")
    offset = 32
    code_size, symbols, entitlements = 0, None, {}
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= len(data), "invalid Mach-O command")
        if command == 0x19:
            for section in range(struct.unpack_from("<I", data, offset + 64)[0]):
                start = offset + 72 + section * 80
                if data[start:start + 16].split(b"\0")[0] == b"__text":
                    code_size = struct.unpack_from("<Q", data, start + 40)[0]
        if command == 0x2:
            symbols = struct.unpack_from("<IIII", data, offset + 8)
        if command == 0x1D:
            position, length = struct.unpack_from("<II", data, offset + 8)
            blob = data[position:position + length]
            require(len(blob) >= 12, "invalid signature container")
            for index in range(struct.unpack_from(">I", blob, 8)[0]):
                _, pos = struct.unpack_from(">II", blob, 12 + index * 8)
                magic, count = struct.unpack_from(">II", blob, pos)
                if magic == 0xFADE7171:
                    entitlements = plistlib.loads(blob[pos + 8:pos + count])
        offset += size
    defined_main = False
    if symbols:
        symbol_offset, count, strings_offset, strings_size = symbols
        strings = data[strings_offset:strings_offset + strings_size]
        for index in range(count):
            label, kind, _, _, address = struct.unpack_from("<IBBHQ", data, symbol_offset + index * 16)
            if (kind & 0x0E) == 0x0E and address and strings.startswith(b"_main\0", label):
                defined_main = True
                break
    return code_size, defined_main, entitlements


def profile(raw):
    result = subprocess.run(["openssl", "cms", "-verify", "-inform", "DER", "-noverify"],
                            input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return plistlib.loads(result.stdout)


def profile_allows_identifier(value, grants):
    return any(value == grant or (grant.endswith("*") and value.startswith(grant[:-1]))
               for grant in grants if isinstance(grant, str))


def verify(path, interactive=False, signed=False):
    files = BundleFiles(path)
    names = files.names()
    extensions = sorted({n.split("/", 2)[1] for n in names
                         if re.fullmatch(r"PlugIns/[^/]+\.appex/Info\.plist", n)})
    require(len(extensions) == 1, "expected exactly one WidgetKit extension")
    paths = ["", f"PlugIns/{extensions[0]}/"]
    infos = [plistlib.loads(files.read(prefix + "Info.plist")) for prefix in paths]
    bundle_ids = [info["CFBundleIdentifier"] for info in infos]
    require(bundle_ids[1].startswith(bundle_ids[0] + "."), "extension ID must be a child of the app ID")
    require(infos[0].get("NSSupportsLiveActivities") is True, "NSSupportsLiveActivities missing")
    require(infos[1].get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension",
            "incorrect WidgetKit extension point")
    configured = [info.get("RitmAppGroup") for info in infos]
    require(configured[0] == configured[1] and configured[0] == "group.app.ritm.personal", "App Group configuration differs")
    summaries, groups = [], []
    for prefix, info in zip(paths, infos):
        executable = info["CFBundleExecutable"]
        require(re.fullmatch(r"[A-Za-z0-9_.-]+", executable), "invalid bundle executable name")
        code_size, main, signature = macho(files.read(prefix + executable))
        require(code_size > 0, f"{executable}: no __text; extension code may have been stripped")
        if prefix:
            require(main, "WidgetBundle _main was stripped or is undefined")
        actual_groups = signature.get("com.apple.security.application-groups", [])
        require(len(actual_groups) == 1, f"{executable}: signature must retain exactly one App Group")
        groups.append(actual_groups)
        metadata_path = prefix + "Metadata.appintents/extract.actionsdata"
        require(metadata_path in names, f"{executable}: metadata index is absent")
        actions = json.loads(files.read(metadata_path))["actions"]
        require(bool(actions) == interactive, f"{executable}: metadata does not match the selected interaction mode")
        for item in actions.values():
            require(item.get("systemProtocols") == ["com.apple.link.systemProtocol.SessionStarting"], "unexpected intent process policy")
            require(item.get("openAppWhenRun") is False, "interactive intent requests foreground launch")
            for key in ["mangledTypeNameByBundleIdentifier", "mangledTypeNameByBundleIdentifierV2"]:
                require(set(item.get(key, {})) == set(bundle_ids), "App Intents routing IDs do not match this bundle")
            parameters = item.get("parameters", [])
            require(len(parameters) == 1 and parameters[0].get("name") == "request"
                    and parameters[0].get("isOptional") is False
                    and parameters[0].get("valueType") == {"primitive": {"wrapper": {"typeIdentifier": 0}}},
                    "unsupported stale-tap request parameter metadata")
        summary = {"bundle": "extension" if prefix else "app", "codeBytes": code_size,
                   "definedMain": main, "appGroupCount": len(actual_groups), "intentCount": len(actions)}
        if signed:
            profile_name = prefix + "embedded.mobileprovision"
            require(profile_name in names, f"{executable}: provisioning profile missing")
            provision = profile(files.read(profile_name))
            allowed = provision["Entitlements"]
            app_identifier = signature.get("application-identifier")
            require(app_identifier == allowed.get("application-identifier"),
                    f"{executable}: signature/profile application identifiers differ (legacy nested signer)")
            require(app_identifier.endswith("." + info["CFBundleIdentifier"]), "signature identifier does not match Info.plist")
            keychain = signature.get("keychain-access-groups", [])
            require(keychain == [app_identifier], f"{executable}: keychain scope is not private to this bundle")
            require(profile_allows_identifier(app_identifier, allowed.get("keychain-access-groups", [])),
                    f"{executable}: private keychain scope not granted by provisioning profile")
            require(signature.get("com.apple.developer.team-identifier") == allowed.get("com.apple.developer.team-identifier"),
                    f"{executable}: signature/profile team identifiers differ")
            if prefix:
                require("com.apple.developer.healthkit" not in signature, "app-only HealthKit entitlement leaked to extension")
            elif signature.get("com.apple.developer.healthkit"):
                require(allowed.get("com.apple.developer.healthkit") is True, "HealthKit not granted by root profile")
            require(set(actual_groups) <= set(allowed.get("com.apple.security.application-groups", [])),
                    f"{executable}: App Group not granted by provisioning profile")
            expiration = provision["ExpirationDate"].replace(tzinfo=dt.timezone.utc)
            require(expiration > dt.datetime.now(dt.timezone.utc), "provisioning profile expired")
            summary["profileExpiration"] = expiration.isoformat()
            summary["privateKeychainScopeVerified"] = True
        summaries.append(summary)
    require(groups[0] == groups[1], "app/extension signatures do not share the same App Group")
    expected_group = "group." + bundle_ids[0]
    require(groups[0] == [expected_group], "actual App Group cannot be resolved from the signed root bundle ID")
    return {"check": "structural", "signedProfileChecks": signed, "interactive": interactive,
            "deviceExecutionVerified": False, "bundles": summaries}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", type=Path)
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("--signed", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = verify(args.path, args.interactive, args.signed)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print("PASS: bundle structure checked; installation, system refresh and action dispatch need an iPhone test.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Bundle verification failed: {error}")
