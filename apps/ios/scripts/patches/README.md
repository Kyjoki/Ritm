# Isolated build-tool patches

These files modify only a generated private tool checkout under `apps/ios/.build/ritm-tools`.
They do not replace the global xtool binary. Apply/build/test without manual source edits:

```bash
bash apps/ios/scripts/prepare-system-toolchain.sh --build-and-test
```

- `xtool-1.24.0-pr284.patch`: upstream App Groups PR #284, merge
  `0c63e6979fd3ebeba3bbd5c8f9eca91142db19ae`, applied to xtool release commit
  `70e1568fdfcb20b560774057cd783f02361293b9`.
- `xtool-1.24.0-per-bundle.patch`: forwards all scoped entitlement entries and adds the isolated
  offline fixture executable target. It does not add a provisioning or installation command.
- `zsign-1.9.0-per-bundle.patch`: local narrow patch for zsign revision
  `f6158be9e62a5ce2a53d72b1a6d880880da956c8`. It checks canonical app boundaries and duplicates,
  requires a root entry, and selects XML per bundle. Missing app/appex entries fail closed;
  helper binaries receive empty entitlements.
- `xtool-1.24.0-group-reuse.patch`: exact owned-group lookup and a bounded read-only refresh
  after a create conflict. It never changes the desired identifier or retries creation.
- `xtool-1.24.0-group-audit.patch`: authenticated read-only diagnostic command that prints
  aggregate owned/matching counts, without group identifiers or auth values.

The two upstream sources are MIT licensed; complete notices are included in this directory.
The metadata emitter and offline fixture are independent Ritm build utilities. No GPL
metadata generator is copied into this repository.

The fixture never reads an Apple auth file, developer private key or device. Its synthetic
App Group is not registered. Actual developer export still needs profile/entitlement checks;
device execution is a separate observation.
