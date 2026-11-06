#!/usr/bin/env bash
# Isolated source patches + offline ad-hoc fixture. Never auths, provisions or installs.
set -euo pipefail
ios_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:---build-and-test}"
[[ "$mode" == --apply-only || "$mode" == --build-and-test ]] || {
  echo 'Usage: bash scripts/prepare-system-toolchain.sh [--apply-only|--build-and-test]' >&2; exit 2;
}
if [[ -f "${HOME}/.local/share/swiftly/env.sh" ]]; then
  source "${HOME}/.local/share/swiftly/env.sh"
fi
bash "$ios_root/scripts/prepare-xtool.sh" --source-only
cache="$ios_root/.build/ritm-tools"
tool_source="$cache/xtool-1.24.0-pr284"
vendor="$cache/zsign-1.9.0-per-bundle"
vendor_revision=f6158be9e62a5ce2a53d72b1a6d880880da956c8
swift_args=(--package-path "$tool_source" --cache-path "$cache/swiftpm-cache" --scratch-path "$tool_source/.build")
if [[ ! -d "$vendor/.git" ]]; then
  swift package "${swift_args[@]}" edit zsign --revision "$vendor_revision" --path "$vendor"
fi
[[ "$(git -C "$vendor" rev-parse HEAD)" == "$vendor_revision" ]] || {
  echo 'Unexpected zsign revision; refusing to patch.' >&2; exit 1;
}
python3 - "$tool_source/.build/workspace-state.json" "$vendor" <<'PY'
import json, pathlib, sys
state, vendor = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve()
data = json.loads(state.read_text())
def strings(value):
    if isinstance(value, str): yield value
    elif isinstance(value, dict):
        for item in value.values(): yield from strings(item)
    elif isinstance(value, list):
        for item in value: yield from strings(item)
if not any(value == str(vendor) for value in strings(data)):
    raise SystemExit("SwiftPM editable override is absent; refusing to build an unpatched dependency")
PY
apply_pinned_patch() {
  local repo="$1" patch="$2"
  if git -C "$repo" apply --check "$patch" 2>/dev/null; then
    git -C "$repo" apply "$patch"
  elif ! git -C "$repo" apply --reverse --check "$patch"; then
    echo "Pinned patch does not match: $patch" >&2; exit 1
  fi
}
apply_pinned_patch "$tool_source" "$ios_root/scripts/patches/xtool-1.24.0-per-bundle.patch"
apply_pinned_patch "$vendor" "$ios_root/scripts/patches/zsign-1.9.0-per-bundle.patch"
apply_pinned_patch "$tool_source" "$ios_root/scripts/patches/xtool-1.24.0-group-audit.patch"
apply_pinned_patch "$tool_source" "$ios_root/scripts/patches/xtool-1.24.0-group-reuse.patch"
cp -- "$ios_root/scripts/fixtures/DSAppGroupsAuditCommand.swift" "$tool_source/Sources/XToolSupport/DSCommands/DSAppGroupsAuditCommand.swift"
mkdir -p -- "$tool_source/RitmSignerFixture"
cp -- "$ios_root/scripts/fixtures/RitmSignerFixture.swift" "$tool_source/RitmSignerFixture/Fixture.swift"
python3 - "$tool_source/ritm-tool-provenance.json" "$ios_root/scripts/patches" "$vendor_revision" <<'PY'
import hashlib, json, pathlib, sys
record, patches, revision = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
data = json.loads(record.read_text())
data["zsignRevision"] = revision
data["perBundlePatches"] = {name: hashlib.sha256((patches/name).read_bytes()).hexdigest()
    for name in ["xtool-1.24.0-per-bundle.patch", "zsign-1.9.0-per-bundle.patch"]}
data["offlineFixtureVerified"] = False
data["groupReusePatchSHA256"] = hashlib.sha256((patches/"xtool-1.24.0-group-reuse.patch").read_bytes()).hexdigest()
data["groupAuditPatchSHA256"] = hashlib.sha256((patches/"xtool-1.24.0-group-audit.patch").read_bytes()).hexdigest()
record.write_text(json.dumps(data, indent=2) + "\n")
PY
if [[ "$mode" == --apply-only ]]; then
  echo 'Isolated patches applied; offline fixture has not run.'
  exit 0
fi
swift build "${swift_args[@]}" --configuration release --product xtool --jobs "${RITM_TOOL_BUILD_JOBS:-2}"
swift build "${swift_args[@]}" --configuration release --product RitmSignerFixture --jobs "${RITM_TOOL_BUILD_JOBS:-2}"
binary="$tool_source/.build/release/xtool"
fixture_binary="$tool_source/.build/release/RitmSignerFixture"
[[ -x "$binary" && -x "$fixture_binary" ]] || { echo 'Expected private executables are absent.' >&2; exit 1; }
"$binary" --version
fixture="$(mktemp -d "$cache/signer-fixture-XXXXXX")"
python3 "$ios_root/scripts/create-signer-fixture.py" "$fixture"
"$fixture_binary" "$fixture/Fixture.app"
python3 - "$tool_source/ritm-tool-provenance.json" "$binary" "$fixture/signer-fixture-report.json" <<'PY'
import hashlib, json, pathlib, sys
record, binary, report = map(pathlib.Path, sys.argv[1:])
result = json.loads(report.read_text())
assert result["kind"] == "offline-ad-hoc" and result["rootOnlyEntitlementDidNotLeak"]
assert result["perBundleIdentifiers"] and result["missingChildRejected"] and result["outsideRootRejected"]
data = json.loads(record.read_text())
data["binarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
data["offlineFixtureVerified"] = True
data["purpose"] = "isolated tool with synthetic ad-hoc fixture only; no developer identity, provisioning or registration"
data["offlineFixtureReport"] = str(report)
data["offlineFixtureReportSHA256"] = hashlib.sha256(report.read_bytes()).hexdigest()
record.write_text(json.dumps(data, indent=2) + "\n")
PY
echo "Validated private tool: $binary"
echo "Offline fixture report: $fixture/signer-fixture-report.json"
echo 'No developer identity, App Group registration, provisioning or device used.'
