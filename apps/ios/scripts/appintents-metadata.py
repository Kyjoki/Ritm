#!/usr/bin/env python3
"""Emit the narrow App Intents index used by Ritm's experimental workout buttons.

This is an independent schema emitter, not Xcode's metadata processor. It accepts
only compiler-confirmed LiveActivityIntent structs with one request: String
parameter. Unknown declarations fail closed. See SYSTEM_FEATURES_BUILD.md.
"""
import argparse
import json
from pathlib import Path


class Unsupported(ValueError):
    pass


TOOLS_FORMAT = "17F113"
SESSION_PROTOCOL = "com.apple.link.systemProtocol.SessionStarting"
ENTRY_KEYS = {"typeName", "mangledTypeName", "kind", "file", "line", "conformances",
              "allConformances", "associatedTypeAliases", "properties"}
INTENT_PROTOCOLS = {"AppIntents.AppIntent", "AppIntents.LiveActivityIntent",
                    "AppIntents.SystemIntent", "AppIntents.PersistentlyIdentifiable",
                    "AppIntents._SupportsAppDependencies"}


def localized(text):
    return {"key": text, "alternatives": []}


def literal(property_value, label, default=None):
    if property_value is None:
        return default
    if property_value.get("valueKind") != "RawLiteral":
        raise Unsupported(f"{label}: expected a compile-time literal")
    return property_value["value"]


def request_parameter(entry):
    wrapped = [p for p in entry["properties"] if p.get("propertyWrappers")]
    if len(wrapped) != 1:
        raise Unsupported(f"{entry['typeName']}: exactly one @Parameter request: String is required")
    parameter = wrapped[0]
    if parameter.get("label") != "request" or parameter.get("type") != "Swift.String":
        raise Unsupported(f"{entry['typeName']}: only nonoptional request: String is supported")
    wrappers = parameter["propertyWrappers"]
    if len(wrappers) != 1 or wrappers[0].get("type") != "AppIntents.IntentParameter":
        raise Unsupported(f"{entry['typeName']}: unknown parameter wrapper")
    arguments = wrappers[0].get("arguments", [])
    if len(arguments) != 1 or arguments[0].get("label") != "title":
        raise Unsupported(f"{entry['typeName']}: @Parameter must declare only a literal title")
    title = literal(arguments[0], "request title")
    # This is the observed Xcode String-parameter data format. Numeric identifier 0
    # is String; 2 and its array are the observed coercible input representations.
    string_type = {"primitive": {"wrapper": {"typeIdentifier": 0}}}
    convertible = {"primitive": {"wrapper": {"typeIdentifier": 2}}}
    return {
        "name": "request", "title": localized(title), "isOptional": False,
        "isInput": False, "capabilities": 0, "dynamicOptionsSupport": 0,
        "inputConnectionBehavior": 0, "typeSpecificMetadata": [],
        "valueType": string_type,
        "resolvableInputTypes": [
            {"kindValue": 0, "valueType": convertible},
            {"kindValue": 0, "valueType": string_type},
            {"kindValue": 0, "valueType": {"array": {"wrapper": {
                "capabilities": 3, "memberValueType": convertible}}}},
        ],
    }


def action(entry, bundle_ids):
    name = entry["typeName"]
    if set(entry) - ENTRY_KEYS or entry.get("kind") != "struct":
        raise Unsupported(f"{name}: unsupported constvalues structure")
    protocols = set(entry.get("conformances", []))
    if not {"AppIntents.AppIntent", "AppIntents.LiveActivityIntent"} <= protocols:
        raise Unsupported(f"{name}: must conform to LiveActivityIntent")
    unknown = {p for p in protocols if p.startswith("AppIntents.")} - INTENT_PROTOCOLS
    if unknown:
        raise Unsupported(f"{name}: unsupported App Intents protocol")
    properties = {p["label"]: p for p in entry.get("properties", [])}
    allowed = {"title", "openAppWhenRun", "isDiscoverable", "request", "_request", "$request"}
    if set(properties) - allowed:
        raise Unsupported(f"{name}: unsupported properties: {sorted(set(properties) - allowed)}")
    title = literal(properties.get("title"), f"{name}.title")
    if not title:
        raise Unsupported(f"{name}: title is required")
    if literal(properties.get("openAppWhenRun"), "openAppWhenRun", "false") != "false":
        raise Unsupported(f"{name}: direct buttons must not request foreground launch")
    discoverable = literal(properties.get("isDiscoverable"), "isDiscoverable", "true") == "true"
    result = next((a for a in entry.get("associatedTypeAliases", [])
                   if a.get("typeAliasName") == "PerformResult"), None)
    if result is None or result.get("opaqueTypeProtocolRequirements") != ["AppIntents.IntentResult"]:
        raise Unsupported(f"{name}: perform must return only some IntentResult")
    mangled = entry.get("mangledTypeName")
    if not isinstance(mangled, str) or not mangled:
        raise Unsupported(f"{name}: compiler mangling is missing")
    routing = dict.fromkeys(bundle_ids, mangled)
    system = [SESSION_PROTOCOL, {"empty": {}}]
    return {
        "identifier": name.rsplit(".", 1)[-1], "fullyQualifiedTypeName": name,
        "title": localized(title), "parameters": [request_parameter(entry)],
        "mangledTypeName": mangled, "mangledTypeNameV2": mangled,
        "mangledTypeNameByBundleIdentifier": routing,
        "mangledTypeNameByBundleIdentifierV2": routing,
        "systemProtocols": [SESSION_PROTOCOL], "systemProtocolMetadata": system,
        "systemProtocolMetadataV2": system, "openAppWhenRun": False,
        "supportedModes": 1, "outputFlags": 0, "authenticationPolicy": 0,
        "isAuthPolExplicit": False, "isDiscoverable": discoverable,
        "visibilityMetadata": {"isDiscoverable": discoverable, "assistantOnly": False},
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "assistantDefinedSchemaTraits": [], "assistantDefinedSchemas": [],
        "effectiveBundleIdentifiers": [], "presentationStyle": 0,
        "requiredCapabilities": [], "typeSpecificMetadata": [],
    }


def index(entries, bundle_ids, module):
    actions = {}
    for entry in entries:
        if not any(p.startswith("AppIntents.") for p in entry.get("conformances", [])):
            continue
        if not entry.get("typeName", "").startswith(module + "."):
            raise Unsupported("constvalues contains an intent from an unexpected module")
        item = action(entry, bundle_ids)
        if item["identifier"] in actions:
            raise Unsupported("duplicate intent identifier")
        actions[item["identifier"]] = item
    return {"actions": actions, "version": 1, "generator": {"name": "xcode-tools", "version": TOOLS_FORMAT},
            "assistantEntities": [], "assistantIntentNegativePhrases": [], "assistantIntents": [],
            "autoShortcuts": [], "entities": {}, "enums": [], "negativePhrases": [], "queries": {},
            "shortcutTileColor": 14}


def compiler_files(root, configuration, module):
    # Output maps describe current inputs, whereas the object directory can retain
    # constvalues from renamed or deleted source files.
    sets = []
    base = root / ".build/out/Intermediates.noindex"
    pattern = f"*.build/{configuration.title()}-iphoneos/{module}-t.build/Objects-normal/arm64/*-OutputFileMap.json"
    mapped = set()
    for output_map in base.glob(pattern):
        for outputs in json.loads(output_map.read_text()).values():
            path = outputs.get("const-values")
            if path:
                candidate = Path(path)
                if not candidate.is_absolute():
                    candidate = root / candidate
                if not candidate.is_file():
                    raise Unsupported(f"missing compiler output listed in {output_map.name}")
                mapped.add(candidate)
    if mapped:
        sets.append(sorted(mapped))
    for directory in (root / ".build").glob(f"arm64-apple-ios*/{configuration}/{module}.build"):
        files = sorted(directory.glob("*.swiftconstvalues"))
        if files:
            sets.append(files)
    if not sets:
        raise Unsupported(f"no compiler constvalues for {module}; build the interactive sources first")
    return max(sets, key=lambda files: max(path.stat().st_mtime_ns for path in files))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ios-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument("--module", default="RitmSystem")
    parser.add_argument("--app-id", default="app.ritm.personal")
    parser.add_argument("--extension-id", default="app.ritm.personal.RitmWidgets")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--const-values", type=Path, action="append")
    parser.add_argument("--seed", action="store_true", help="write an empty index for baseline/bootstrap builds")
    parser.add_argument("--check", action="store_true", help="compare only; never write")
    args = parser.parse_args()
    output = args.output or args.ios_root / ".build/ritm-appintents"
    files = [] if args.seed else (args.const_values or compiler_files(args.ios_root, args.configuration, args.module))
    entries = [entry for path in files for entry in json.loads(path.read_text(encoding="utf-8"))]
    data = index(entries, [args.app_id, args.extension_id], args.module)
    if not args.seed and not data["actions"]:
        raise Unsupported("no interactive intents found; refusing to emit an apparently enabled empty index")
    rendered = {"extract.actionsdata": data, "version.json": {"version": "3.0", "toolsVersion": TOOLS_FORMAT}}
    for bundle in ["Ritm", "RitmWidgets"]:
        for filename, value in rendered.items():
            path = output / bundle / "Metadata.appintents" / filename
            text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            if args.check:
                if not path.is_file() or path.read_text(encoding="utf-8") != text:
                    raise Unsupported(f"stale metadata: {path}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    print(f"{'Checked' if args.check else 'Prepared'} App Intents index: {len(data['actions'])} actions; device dispatch unverified")


if __name__ == "__main__":
    try:
        main()
    except (Unsupported, OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"App Intents metadata refused: {error}")
