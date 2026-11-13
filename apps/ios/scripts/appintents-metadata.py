#!/usr/bin/env python3
"""Emit the narrow App Intents index used by Ritm's experimental system actions.

This is an independent schema emitter, not Xcode's metadata processor. It accepts only
compiler-confirmed shapes and fails closed on anything else:
  * RitmSystem: LiveActivityIntent structs with one request: String parameter (workout
    buttons; listed in the app AND the widget extension index, not discoverable);
  * Ritm (the app module): plain AppIntent structs whose parameters are all required String
    values with literal titles (the Shortcuts action "record purchase"; listed in the APP
    index only, discoverable, background-only). Without a custom parameterSummary the system
    builds the default action row from the parameter titles.
See SYSTEM_FEATURES_BUILD.md.
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
# A plain app action is only an AppIntent: no system protocol of any kind.
PLAIN_PROTOCOLS = {"AppIntents.AppIntent", "AppIntents.PersistentlyIdentifiable",
                   "AppIntents._SupportsAppDependencies"}
MAX_PLAIN_PARAMETERS = 8
# The default parameterSummary the framework supplies; a custom one cannot be emitted yet.
DEFAULT_SUMMARY = "10AppIntents0A6IntentPAAE16parameterSummary"


def localized(text):
    return {"key": text, "alternatives": []}


def literal(property_value, label, default=None):
    if property_value is None:
        return default
    if property_value.get("valueKind") != "RawLiteral":
        raise Unsupported(f"{label}: expected a compile-time literal")
    return property_value["value"]


def string_parameter(name, title):
    # This is the observed Xcode String-parameter data format. Numeric identifier 0
    # is String; 2 and its array are the observed coercible input representations.
    string_type = {"primitive": {"wrapper": {"typeIdentifier": 0}}}
    convertible = {"primitive": {"wrapper": {"typeIdentifier": 2}}}
    return {
        "name": name, "title": localized(title), "isOptional": False,
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


def literal_title_parameter(entry, parameter):
    """Name and literal title of a nonoptional String @Parameter that declares only a title."""
    name = parameter.get("label")
    if parameter.get("type") != "Swift.String":
        raise Unsupported(f"{entry['typeName']}.{name}: only nonoptional String parameters are supported")
    wrappers = parameter["propertyWrappers"]
    if len(wrappers) != 1 or wrappers[0].get("type") != "AppIntents.IntentParameter":
        raise Unsupported(f"{entry['typeName']}: unknown parameter wrapper")
    arguments = wrappers[0].get("arguments", [])
    if len(arguments) != 1 or arguments[0].get("label") != "title":
        raise Unsupported(f"{entry['typeName']}: @Parameter must declare only a literal title")
    return name, literal(arguments[0], f"{name} title")


def request_parameter(entry):
    wrapped = [p for p in entry["properties"] if p.get("propertyWrappers")]
    if len(wrapped) != 1:
        raise Unsupported(f"{entry['typeName']}: exactly one @Parameter request: String is required")
    if wrapped[0].get("label") != "request":
        raise Unsupported(f"{entry['typeName']}: only nonoptional request: String is supported")
    name, title = literal_title_parameter(entry, wrapped[0])
    return string_parameter(name, title)


def common_action(name, entry, title, discoverable, routing, parameters, protocols):
    mangled = entry["mangledTypeName"]
    system = [] if not protocols else [protocols[0], {"empty": {}}]
    return {
        "identifier": name.rsplit(".", 1)[-1], "fullyQualifiedTypeName": name,
        "title": localized(title), "parameters": parameters,
        "mangledTypeName": mangled, "mangledTypeNameV2": mangled,
        "mangledTypeNameByBundleIdentifier": routing,
        "mangledTypeNameByBundleIdentifierV2": routing,
        "systemProtocols": protocols, "systemProtocolMetadata": system,
        "systemProtocolMetadataV2": system, "openAppWhenRun": False,
        "supportedModes": 1, "outputFlags": 0, "authenticationPolicy": 0,
        "isAuthPolExplicit": False, "isDiscoverable": discoverable,
        "visibilityMetadata": {"isDiscoverable": discoverable, "assistantOnly": False},
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "assistantDefinedSchemaTraits": [], "assistantDefinedSchemas": [],
        "effectiveBundleIdentifiers": [], "presentationStyle": 0,
        "requiredCapabilities": [], "typeSpecificMetadata": [],
    }


def check_common(entry, protocols, allowed_properties):
    name = entry["typeName"]
    if set(entry) - ENTRY_KEYS or entry.get("kind") != "struct":
        raise Unsupported(f"{name}: unsupported constvalues structure")
    unknown = {p for p in protocols if p.startswith("AppIntents.")} - INTENT_PROTOCOLS
    if unknown:
        raise Unsupported(f"{name}: unsupported App Intents protocol")
    properties = {p["label"]: p for p in entry.get("properties", [])}
    extra = set(properties) - allowed_properties
    if extra:
        raise Unsupported(f"{name}: unsupported properties: {sorted(extra)}")
    title = literal(properties.get("title"), f"{name}.title")
    if not title:
        raise Unsupported(f"{name}: title is required")
    if literal(properties.get("openAppWhenRun"), "openAppWhenRun", "false") != "false":
        raise Unsupported(f"{name}: system actions must not request foreground launch")
    discoverable = literal(properties.get("isDiscoverable"), "isDiscoverable", "true") == "true"
    result = next((a for a in entry.get("associatedTypeAliases", [])
                   if a.get("typeAliasName") == "PerformResult"), None)
    if result is None or result.get("opaqueTypeProtocolRequirements") != ["AppIntents.IntentResult"]:
        raise Unsupported(f"{name}: perform must return only some IntentResult")
    mangled = entry.get("mangledTypeName")
    if not isinstance(mangled, str) or not mangled:
        raise Unsupported(f"{name}: compiler mangling is missing")
    return title, discoverable


def action(entry, bundle_ids):
    name = entry["typeName"]
    protocols = set(entry.get("conformances", []))
    if not {"AppIntents.AppIntent", "AppIntents.LiveActivityIntent"} <= protocols:
        raise Unsupported(f"{name}: must conform to LiveActivityIntent")
    allowed = {"title", "openAppWhenRun", "isDiscoverable", "request", "_request", "$request"}
    title, discoverable = check_common(entry, protocols, allowed)
    return common_action(name, entry, title, discoverable, dict.fromkeys(bundle_ids, entry["mangledTypeName"]),
                         [request_parameter(entry)], [SESSION_PROTOCOL])


def plain_action(entry, app_id):
    """A discoverable AppIntent with required String parameters, routed to the app bundle only."""
    name = entry["typeName"]
    protocols = {p for p in entry.get("conformances", []) if p.startswith("AppIntents.")}
    if "AppIntents.AppIntent" not in protocols or protocols - PLAIN_PROTOCOLS:
        raise Unsupported(f"{name}: only a plain AppIntent (no system protocol) is supported here")
    wrapped = [p for p in entry.get("properties", []) if p.get("propertyWrappers")]
    labels = [p["label"] for p in wrapped]
    allowed = {"title", "openAppWhenRun", "isDiscoverable"}
    allowed |= set(labels) | {"_" + x for x in labels} | {"$" + x for x in labels}
    title, discoverable = check_common(entry, protocols, allowed)
    if not 1 <= len(wrapped) <= MAX_PLAIN_PARAMETERS or len(set(labels)) != len(labels):
        raise Unsupported(f"{name}: expected 1..{MAX_PLAIN_PARAMETERS} uniquely named @Parameter values")
    if any(label.startswith(("_", "$")) for label in labels):
        raise Unsupported(f"{name}: unexpected parameter name")
    for alias in entry.get("associatedTypeAliases", []):
        if alias.get("typeAliasName") == "SummaryContent" and (
                DEFAULT_SUMMARY not in alias.get("substitutedMangledTypeName", "")):
            raise Unsupported(f"{name}: a custom parameterSummary is not supported")
    parameters = [string_parameter(*literal_title_parameter(entry, p)) for p in wrapped]
    return common_action(name, entry, title, discoverable, {app_id: entry["mangledTypeName"]},
                         parameters, [])


def document(actions):
    return {"actions": actions, "version": 1, "generator": {"name": "xcode-tools", "version": TOOLS_FORMAT},
            "assistantEntities": [], "assistantIntentNegativePhrases": [], "assistantIntents": [],
            "autoShortcuts": [], "entities": {}, "enums": [], "negativePhrases": [], "queries": {},
            "shortcutTileColor": 14}


def indexes(entries, bundle_ids, module, app_module=None):
    """Returns {bundle: document}. Workout actions go to both bundles; plain app actions
    (module `app_module`) only to the first bundle ID's index, the application."""
    shared, app_only = {}, {}
    for entry in entries:
        if not any(p.startswith("AppIntents.") for p in entry.get("conformances", [])):
            continue
        type_name = entry.get("typeName", "")
        if type_name.startswith(module + "."):
            target, item = shared, action(entry, bundle_ids)
        elif app_module and type_name.startswith(app_module + "."):
            target, item = app_only, plain_action(entry, bundle_ids[0])
        else:
            raise Unsupported("constvalues contains an intent from an unexpected module")
        if item["identifier"] in shared or item["identifier"] in app_only:
            raise Unsupported("duplicate intent identifier")
        target[item["identifier"]] = item
    return {"Ritm": document({**shared, **app_only}), "RitmWidgets": document(shared)}


def index(entries, bundle_ids, module):
    """The index every bundle gets when only shared (workout) actions exist."""
    return indexes(entries, bundle_ids, module)["Ritm"]


def module_files(root, configuration, module):
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


def compiler_files(root, configuration, module, app_module=None):
    files = list(module_files(root, configuration, module))
    if app_module:
        files += module_files(root, configuration, app_module)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ios-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument("--module", default="RitmSystem")
    parser.add_argument("--app-module", default="Ritm")
    parser.add_argument("--app-id", default="app.ritm.personal")
    parser.add_argument("--extension-id", default="app.ritm.personal.RitmWidgets")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--const-values", type=Path, action="append")
    parser.add_argument("--seed", action="store_true", help="write an empty index for baseline/bootstrap builds")
    parser.add_argument("--check", action="store_true", help="compare only; never write")
    args = parser.parse_args()
    output = args.output or args.ios_root / ".build/ritm-appintents"
    files = [] if args.seed else (args.const_values or compiler_files(
        args.ios_root, args.configuration, args.module, args.app_module))
    entries = [entry for path in files for entry in json.loads(path.read_text(encoding="utf-8"))]
    per_bundle = indexes(entries, [args.app_id, args.extension_id], args.module, args.app_module)
    if not args.seed and not per_bundle["RitmWidgets"]["actions"]:
        raise Unsupported("no interactive intents found; refusing to emit an apparently enabled empty index")
    for bundle, data in per_bundle.items():
        rendered = {"extract.actionsdata": data, "version.json": {"version": "3.0", "toolsVersion": TOOLS_FORMAT}}
        for filename, value in rendered.items():
            path = output / bundle / "Metadata.appintents" / filename
            text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            if args.check:
                if not path.is_file() or path.read_text(encoding="utf-8") != text:
                    raise Unsupported(f"stale metadata: {path}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    counts = {bundle: len(data["actions"]) for bundle, data in per_bundle.items()}
    detail = f"{counts['Ritm']} actions"
    if counts["Ritm"] != counts["RitmWidgets"]:
        detail += f" (app {counts['Ritm']}, widget extension {counts['RitmWidgets']})"
    print(f"{'Checked' if args.check else 'Prepared'} App Intents index: {detail}; device dispatch unverified")


if __name__ == "__main__":
    try:
        main()
    except (Unsupported, OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"App Intents metadata refused: {error}")
