#!/usr/bin/env python3
"""Regression tests for scripts/appintents-metadata.py (no Apple tools, no device).

  python3 apps/ios/scripts/test-appintents-metadata.py

The golden files were produced by the emitter BEFORE the plain-AppIntent support existed and
copied from a real build's RitmSystem constvalues: the workout-only output must stay
byte-for-byte identical. The purchase fixture is the real compiler output of
Sources/Ritm/PurchaseIntent.swift.
"""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "appintents"
EMITTER = HERE / "appintents-metadata.py"
APP, EXTENSION = "XTL-TEST.app.ritm.personal", "XTL-TEST.app.ritm.personal.RitmWidgets"


def emit(*const_values, extra=()):
    """Runs the emitter; returns (exit code, output text, directory with the written index)."""
    out = Path(tempfile.mkdtemp(prefix="appintents-test-"))
    command = [sys.executable, str(EMITTER), "--app-id", APP, "--extension-id", EXTENSION,
               "--output", str(out), *extra]
    for path in const_values:
        command += ["--const-values", str(path)]
    result = subprocess.run(command, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr, out


def read(out, bundle, name="extract.actionsdata"):
    return (out / bundle / "Metadata.appintents" / name).read_text(encoding="utf-8")


def mutated(source, change, tmp):
    entries = json.loads(Path(source).read_text(encoding="utf-8"))
    change(entries[0])
    path = Path(tmp) / "mutated.swiftconstvalues"
    path.write_text(json.dumps(entries), encoding="utf-8")
    return path


class WorkoutOutputIsUnchanged(unittest.TestCase):
    workout = FIXTURES / "RitmSystem-workout.swiftconstvalues"
    golden = (FIXTURES / "golden" / "workout-only.extract.actionsdata").read_text(encoding="utf-8")

    def test_both_bundles_match_the_pre_change_output_byte_for_byte(self):
        code, text, out = emit(self.workout)
        self.assertEqual(code, 0, text)
        self.assertEqual(read(out, "Ritm"), self.golden)
        self.assertEqual(read(out, "RitmWidgets"), self.golden)
        self.assertEqual(read(out, "Ritm", "version.json"),
                         (FIXTURES / "golden" / "version.json").read_text(encoding="utf-8"))

    def test_an_empty_app_module_changes_nothing(self):
        code, text, out = emit(self.workout, FIXTURES / "Ritm-empty.swiftconstvalues")
        self.assertEqual(code, 0, text)
        self.assertEqual(read(out, "Ritm"), self.golden)
        self.assertEqual(read(out, "RitmWidgets"), self.golden)

    def test_the_bootstrap_seed_is_unchanged(self):
        code, text, out = emit(extra=["--seed"])
        self.assertEqual(code, 0, text)
        seed = (FIXTURES / "golden" / "seed.extract.actionsdata").read_text(encoding="utf-8")
        self.assertEqual(read(out, "Ritm"), seed)
        self.assertEqual(read(out, "RitmWidgets"), seed)

    def test_check_mode_accepts_what_was_written(self):
        _, _, out = emit(self.workout)
        result = subprocess.run([sys.executable, str(EMITTER), "--app-id", APP, "--extension-id", EXTENSION,
                                 "--output", str(out), "--const-values", str(self.workout), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class PurchaseAction(unittest.TestCase):
    workout = FIXTURES / "RitmSystem-workout.swiftconstvalues"
    purchase = FIXTURES / "Ritm-purchase.swiftconstvalues"

    def setUp(self):
        code, text, self.out = emit(self.workout, self.purchase)
        self.assertEqual(code, 0, text)
        self.app = json.loads(read(self.out, "Ritm"))["actions"]
        self.widget = json.loads(read(self.out, "RitmWidgets"))["actions"]

    def test_the_app_index_lists_both_actions_and_the_widget_index_only_the_workout_one(self):
        self.assertEqual(sorted(self.app), ["RecordPurchaseIntent", "RitmWorkoutActionIntent"])
        self.assertEqual(sorted(self.widget), ["RitmWorkoutActionIntent"])

    def test_the_workout_action_is_identical_in_both_indexes_and_in_the_golden_file(self):
        golden = json.loads((FIXTURES / "golden" / "workout-only.extract.actionsdata").read_text(encoding="utf-8"))
        self.assertEqual(self.app["RitmWorkoutActionIntent"], golden["actions"]["RitmWorkoutActionIntent"])
        self.assertEqual(self.widget["RitmWorkoutActionIntent"], golden["actions"]["RitmWorkoutActionIntent"])
        self.assertEqual(read(self.out, "RitmWidgets"),
                         (FIXTURES / "golden" / "workout-only.extract.actionsdata").read_text(encoding="utf-8"))

    def test_the_purchase_action_is_a_discoverable_background_app_action(self):
        item = self.app["RecordPurchaseIntent"]
        self.assertEqual(item["fullyQualifiedTypeName"], "Ritm.RecordPurchaseIntent")
        self.assertEqual(item["title"], {"key": "Записать покупку", "alternatives": []})
        self.assertIs(item["openAppWhenRun"], False)
        self.assertIs(item["isDiscoverable"], True)
        self.assertEqual(item["visibilityMetadata"], {"isDiscoverable": True, "assistantOnly": False})
        self.assertEqual((item["systemProtocols"], item["systemProtocolMetadata"]), ([], []))
        self.assertEqual(item["authenticationPolicy"], 0)
        self.assertEqual(item["mangledTypeNameByBundleIdentifier"], {APP: item["mangledTypeName"]})
        self.assertEqual(item["mangledTypeNameByBundleIdentifierV2"], {APP: item["mangledTypeName"]})

    def test_the_parameters_are_five_required_strings_in_declaration_order(self):
        parameters = self.app["RecordPurchaseIntent"]["parameters"]
        self.assertEqual([(p["name"], p["title"]["key"]) for p in parameters],
                         [("amount", "Сумма"), ("merchant", "Магазин"), ("card", "Карта"),
                          ("date", "Дата"), ("at", "Время")])
        for parameter in parameters:
            self.assertIs(parameter["isOptional"], False)
            self.assertEqual(parameter["valueType"], {"primitive": {"wrapper": {"typeIdentifier": 0}}})

    def test_a_parameter_has_the_same_shape_as_the_observed_workout_string_parameter(self):
        request = self.app["RitmWorkoutActionIntent"]["parameters"][0]
        amount = self.app["RecordPurchaseIntent"]["parameters"][0]
        self.assertEqual({k: v for k, v in amount.items() if k not in ("name", "title")},
                         {k: v for k, v in request.items() if k not in ("name", "title")})


class UnknownShapesFailClosed(unittest.TestCase):
    workout = FIXTURES / "RitmSystem-workout.swiftconstvalues"
    purchase = FIXTURES / "Ritm-purchase.swiftconstvalues"

    def refused(self, source, change, *others):
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = emit(mutated(source, change, tmp), *others)
        self.assertNotEqual(code, 0, text)
        self.assertIn("App Intents metadata refused", text)

    def prop(self, entry, label):
        return next(p for p in entry["properties"] if p["label"] == label)

    def test_purchase_variants_are_refused(self):
        def optional(e):
            self.prop(e, "card")["type"] = "Swift.Optional<Swift.String>"
        def integer(e):
            self.prop(e, "amount")["type"] = "Swift.Int"
        def default_value(e):
            self.prop(e, "card")["propertyWrappers"][0]["arguments"].append(
                {"label": "default", "valueKind": "RawLiteral", "value": "x"})
        def runtime_title(e):
            self.prop(e, "card")["propertyWrappers"][0]["arguments"][0]["valueKind"] = "Runtime"
        def foreground(e):
            self.prop(e, "openAppWhenRun")["value"] = "true"
        def system_protocol(e):
            e["conformances"].append("AppIntents.SystemIntent")
        def other_protocol(e):
            e["conformances"].append("AppIntents.AppEntity")
        def custom_summary(e):
            for alias in e["associatedTypeAliases"]:
                if alias["typeAliasName"] == "SummaryContent":
                    alias["substitutedMangledTypeName"] = "4Ritm20RecordPurchaseIntentV16parameterSummary"
        def dialog_result(e):
            for alias in e["associatedTypeAliases"]:
                if alias["typeAliasName"] == "PerformResult":
                    alias["opaqueTypeProtocolRequirements"] = ["AppIntents.IntentResult", "AppIntents.ProvidesDialog"]
        def stray_property(e):
            e["properties"].append(dict(self.prop(e, "title"), label="description"))
        def no_title(e):
            self.prop(e, "title")["value"] = ""
        def too_many(e):
            for index in range(9):
                clone = copy.deepcopy(self.prop(e, "card"))
                clone["label"] = f"extra{index}"
                e["properties"].append(clone)
        variants = [(n, f) for n, f in locals().items() if n != "self" and callable(f)]
        self.assertEqual(len(variants), 12)
        for name, change in variants:
            with self.subTest(name):
                self.refused(self.purchase, change, self.workout)

    def test_an_intent_from_another_module_is_refused(self):
        self.refused(self.purchase, lambda e: e.update(typeName="Other.RecordPurchaseIntent"), self.workout)

    def test_a_duplicate_identifier_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = json.loads(self.purchase.read_text(encoding="utf-8"))
            clone = copy.deepcopy(entries[0])
            clone["typeName"] = "RitmSystem.RecordPurchaseIntent"
            both = Path(tmp) / "dup.swiftconstvalues"
            both.write_text(json.dumps(entries + [clone]), encoding="utf-8")
            code, text, _ = emit(self.workout, both)
        self.assertNotEqual(code, 0, text)

    def test_a_live_activity_intent_in_the_app_module_is_refused(self):
        def live(entry):
            entry["conformances"] += ["AppIntents.LiveActivityIntent", "AppIntents.SystemIntent"]
        self.refused(self.purchase, live, self.workout)

    def test_workout_variants_stay_refused(self):
        self.refused(self.workout, lambda e: e["conformances"].remove("AppIntents.LiveActivityIntent"))
        self.refused(self.workout, lambda e: self.prop(e, "openAppWhenRun").update(value="true"))
        self.refused(self.workout, lambda e: self.prop(e, "request").update(label="other"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
