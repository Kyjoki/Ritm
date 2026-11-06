#!/usr/bin/env bash
# Builds a private tool; never replaces ~/.local/bin/xtool, authenticates or provisions.
set -euo pipefail
ios_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:---source-only}"
if [[ "$mode" != --source-only && "$mode" != --build ]]; then
  echo 'Usage: bash scripts/prepare-xtool.sh [--source-only|--build]' >&2
  exit 2
fi
source_commit=70e1568fdfcb20b560774057cd783f02361293b9
pr_merge_commit=0c63e6979fd3ebeba3bbd5c8f9eca91142db19ae
cache="$ios_root/.build/ritm-tools"
source_dir="$cache/xtool-1.24.0-pr284"
patch="$ios_root/scripts/patches/xtool-1.24.0-pr284.patch"
mkdir -p -- "$cache"
if [[ ! -d "$source_dir" ]]; then
  # Public upstream only; no credential helper or prompt is needed.
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.autocrlf=false clone \
    --filter=blob:none --no-checkout https://github.com/xtool-org/xtool.git "$source_dir"
  git -C "$source_dir" checkout --detach "$source_commit"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$source_commit" ]] || {
  echo 'Refusing to modify a tool checkout at an unexpected commit.' >&2; exit 1;
}
if git -C "$source_dir" apply --check "$patch" 2>/dev/null; then
  [[ -z "$(git -C "$source_dir" status --porcelain)" ]] || {
    echo 'Refusing to patch a tool checkout with unrelated changes.' >&2; exit 1;
  }
  git -C "$source_dir" apply "$patch"
elif ! git -C "$source_dir" apply --reverse --check "$patch"; then
  echo 'Pinned PR #284 patch does not match this checkout.' >&2; exit 1
fi
python3 - "$source_dir" "$source_commit" "$pr_merge_commit" "$patch" <<'PY'
import hashlib, json, pathlib, sys
root, base, upstream, patch = sys.argv[1:]
data = {"source": "https://github.com/xtool-org/xtool", "baseCommit": base,
        "upstreamPR": 284, "upstreamMergeCommit": upstream,
        "patchSHA256": hashlib.sha256(pathlib.Path(patch).read_bytes()).hexdigest(),
        "purpose": "one App Group per free-team app; no signing or registration performed"}
pathlib.Path(root, "ritm-tool-provenance.json").write_text(json.dumps(data, indent=2) + "\n")
PY
echo "Tool source: $source_dir"
echo 'Pinned xtool 1.24.0 + upstream PR #284; global xtool is unchanged.'
if [[ "$mode" == --build ]]; then
  if [[ -f "${HOME}/.local/share/swiftly/env.sh" ]]; then
    source "${HOME}/.local/share/swiftly/env.sh"
  fi
  command -v swift >/dev/null
  swift build --package-path "$source_dir" --configuration release --product xtool \
    --cache-path "$cache/swiftpm-cache" --scratch-path "$source_dir/.build" \
    --jobs "${RITM_TOOL_BUILD_JOBS:-2}"
  binary="$source_dir/.build/release/xtool"
  [[ -x "$binary" ]] || { echo 'Build did not produce a private executable.' >&2; exit 1; }
  "$binary" --version
  python3 - "$source_dir" "$binary" <<'PY'
import hashlib, json, pathlib, sys
source, binary = map(pathlib.Path, sys.argv[1:])
record = source / "ritm-tool-provenance.json"
value = json.loads(record.read_text())
value["binarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
resolved = source / "Package.resolved"
if resolved.is_file():
    value["resolvedDependenciesSHA256"] = hashlib.sha256(resolved.read_bytes()).hexdigest()
record.write_text(json.dumps(value, indent=2) + "\n")
PY
  echo "Private binary: $binary"
  echo "Select explicitly: RITM_XTOOL='$binary'"
fi
