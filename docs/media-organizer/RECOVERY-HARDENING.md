# Recovery hardening checkpoint

## Interrupted Undo follow-up

Two additional regression cases reproduced a production state-transition bug:
failed reconciliation changed `undoing` into generic `needsReview`, losing the
direction of the operation. Subsequent verification could classify a partially
undone move as a forward copy, or fail to recognize a completed Undo after
disconnected storage returned.

Reconciliation now preserves `undoing` on failure. Repeated verification stays
read-only, forward execution remains blocked, and fully completed Undo can be
recognized after storage returns. Partially completed Undo still requires manual
inspection; this fix does not introduce automatic filesystem replay. Previously
ambiguous records are not guessed or silently migrated.

Both new tests failed before the fix. The updated host suite has **21 passing
JUnit tests**. This production Kotlin change requires a full Android build; the
previous Dart-only APK updater must refuse it. The published APK does not yet
include this fix. The original checkpoint below changed tests only.

The next release begins with storage verification. `OrganizerCrashBoundaryTest`
simulates abrupt process termination immediately before and immediately after
each journal write in copy and move workflows. Termination bypasses the ordinary
exception handler, leaving only the previously committed journal state. A fresh
worker then resumes only operations with established output ownership.

The tests require complete original bytes to survive each interruption and the
subsequent retry. They also verify unrelated destination bytes remain unchanged,
completed copies match, moves retain originals in Trash, and outputs lacking a
durable creation receipt remain unclaimed. Only disposable generated fixtures are
used. The journal double models atomic committed writes; it does not establish
Android AtomicFile, Keystore, flash durability or USB provider behavior.

Validation on the Linux host: **19 JUnit tests passed**, comprising the 17 existing
transfer cases and two exhaustive journal-boundary sweeps. Production code and
the signed APK are unchanged by this checkpoint. No tablet/Android SDK is
available in this execution environment; no device test or new APK is claimed.

Run using an existing trusted Kotlin compiler distribution, JUnit 4 and Hamcrest:

```sh
python3 tool/privacy/run_organizer_host_tests.py \
  --kotlinc /path/to/kotlinc/bin/kotlinc \
  --junit /path/to/junit.jar --hamcrest /path/to/hamcrest.jar
```

Next: restore an Android SDK build environment, then implement a vault-specific
storage adapter. The current organizer adapter accepts raw paths and approved
Android external-storage document trees; a mounted encrypted vault cannot be
enabled merely by removing the UI guard. Vault access must establish session
validity, exclusive output creation, streaming writes, stable ownership and
verified recovery before allowing mutation. Container-passphrase protection for
generated records is a separate requirement from the existing app Keystore.

Hardware acceptance remains in PHOTO-WORKFLOW.md. In particular, USB removal,
grant revocation, force-stop and power loss need real Android testing; host
fault injection does not replace those checks.
