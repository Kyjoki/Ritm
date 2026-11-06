#!/usr/bin/env bash
# Unsigned only: no auth, App Group registration, developer provisioning or phone access.
set -euo pipefail
ios_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"
[[ "$configuration" == debug || "$configuration" == release ]] || {
  echo 'Usage: bash scripts/build-system-features.sh [debug|release]' >&2; exit 2;
}
interactive="${RITM_INTERACTIVE:-0}"
[[ "$interactive" == 0 || "$interactive" == 1 ]] || { echo 'RITM_INTERACTIVE must be 0 or 1.' >&2; exit 2; }
[[ "${RITM_CORE_TESTS_ONLY:-0}" != 1 ]] || { echo 'Unset RITM_CORE_TESTS_ONLY before an iOS build.' >&2; exit 2; }
export RITM_INTERACTIVE="$interactive"
if [[ -f "${HOME}/.local/share/swiftly/env.sh" ]]; then
  source "${HOME}/.local/share/swiftly/env.sh"
fi
export PATH="${HOME}/.local/bin:${PATH}"
tool="${RITM_XTOOL:-xtool}"
command -v "$tool" >/dev/null
command -v swift >/dev/null
command -v python3 >/dev/null
cd -- "$ios_root"
artifact_root="${RITM_ARTIFACT_ROOT:-$ios_root/.build/ritm-artifacts}"
mkdir -p -- .build/ritm-logs "$artifact_root"
log="$ios_root/.build/ritm-logs/$configuration-$interactive.log"
python3 scripts/appintents-metadata.py --seed
started_ns="$(python3 -c 'import time; print(time.time_ns())')"
"$tool" dev build --configuration "$configuration" 2>&1 | tee "$log"
bundle="$(python3 scripts/verify-build-log.py "$log" --started-ns "$started_ns")"
if [[ "$interactive" == 1 ]]; then
  app_id="${RITM_METADATA_APP_ID:-app.ritm.personal}"
  extension_id="${RITM_METADATA_EXTENSION_ID:-$app_id.RitmWidgets}"
  python3 scripts/appintents-metadata.py --configuration "$configuration" \
    --app-id "$app_id" --extension-id "$extension_id"
  started_ns="$(python3 -c 'import time; print(time.time_ns())')"
  "$tool" dev build --configuration "$configuration" 2>&1 | tee "$log"
  bundle="$(python3 scripts/verify-build-log.py "$log" --started-ns "$started_ns")"
fi
artifact_dir="$(mktemp -d "$artifact_root/$configuration-$interactive-XXXXXX")"
python3 - "$bundle" "$artifact_dir" <<'PY'
import pathlib, shutil, sys
source, destination = map(pathlib.Path, sys.argv[1:])
shutil.copytree(source, destination / "Ritm.app")
PY
verify_flags=()
if [[ "$interactive" == 1 ]]; then verify_flags+=(--interactive); fi
python3 scripts/verify-system-bundle.py "$artifact_dir/Ritm.app" \
  "${verify_flags[@]}" --report "$artifact_dir/structure.json"
echo "Unsigned review artifact: $artifact_dir/Ritm.app"
echo 'No provisioning or installation performed. App Group sharing and interactive dispatch still require device checks.'
