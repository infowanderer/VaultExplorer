# Recovery hardening checkpoint

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
