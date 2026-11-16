# Hosted native lifecycle clock fixture

## Boundary and cause

Issue [#554](https://github.com/syncomm/voodootrackerx/issues/554) exposed slow
CoreAudio delivery on the hosted AppleVirtIOSound device. The failed native test
received 15 callbacks / 7,680 frames in ten seconds, with continuing callbacks
and repeated HAL clock reanchors. The C retirement deadline had not been reached.
A standalone silent DefaultOutput program reproduces this without VTX code.

Read-only driver inspection, a deterministic scheduling model and clock logs
support a stale first-timer mechanism: short sessions leave delayed timers that
adopt a later session's seed. After an idle gap, these chains produce future
timestamps and persistent reanchoring. Runtime timer queues/seeds were not directly
observed. Keeping another unit active in the same process prevents the global
device/context idle transitions tested by the controlled comparison.
This is a test-environment repair; it does not repair the OS driver or establish
production recovery from that driver defect.

## Approved fixture contract

Only `LoopEngineLifecycleTests` may activate the fixture, and only with explicit
hosted-CI flags. One independent silent 48 kHz DefaultOutput unit runs from class
setup through class teardown. Ordinary local tests and production playback do
not activate it. No package tests, other XCTest classes, or trap probes use it.

Readiness requires that unit's own 48,000 frames within ten monotonic seconds.
Every test checks its running state, device identity and callback health.
Teardown requires successful Stop, uninitialize, disposal and callback quiescence.
Stage-specific receipts must match independently attributed executed-test PIDs;
missing, stale, malformed, foreign or incomplete receipts fail qualification.
These receipts remain separate from the unchanged ASan process/image/initializer
evidence. The original test manifests, Release checks and four traps remain gates.

Each tested VTX unit still starts, stops and disposes independently. Its own
callback/native counters, producer blockade, unserviced Main actor, terminal
boundary plus 240-frame retirement, cancellation and late-work assertions remain
authoritative. The fixture cannot credit frames to a target or repair a deadlocked
mixer. The blocked-producer scenario runs twenty fixed iterations; every original
ten-second deadline and assertion remains, and failures cannot be erased by later
iterations. The fixture adds no production callback allocation, lock or session.

## Controlled comparison and evidence

`.github/scripts/issue554-host-progress.c` provides twenty targets per mode:
baseline, immediate restart, idle restart and guarded idle restart. Each target
requires its own 48,000 frames within ten seconds. Idle modes reuse one initialized
unit for three short primers, require their completion within 260 ms, then wait at
least 500 ms before a fresh target. Missing timing/device/callback preconditions
are incomplete evidence, never a passing witness. Guard readiness, independent
progress and teardown also gate the guarded mode.
The serial probe caller explicitly requests and verifies user-interactive QoS in
every mode, and records Stop-call entry separately from return. This controls a
scheduling hypothesis about long stop-return delays; it does not establish the
XCTest caller's QoS or relax the interleaving criteria.

The unguarded idle mode remains explicitly non-voting driver evidence, with raw
failures and clock logs retained. Its result must not be reported as successful
native-device qualification. Baseline, immediate restart, guarded control, Debug,
native ASan and optimized Release remain strict gates. CI retains receipts and
xcresults in its artifacts; local diagnostic outputs use `/private/tmp/vtx-.../`.

## Outstanding native-device obligation

This fixture does **not** qualify globally idle-device startup, device stop/start,
or fully cold process audio-context latency. Before the backend freeze, Codex must
qualify those paths unassisted on a native arm64 device/driver unaffected by this
defect, with exact source/product provenance, original progress deadlines and
equivalent cached-start latency inputs. Gregory owns acceptance of that evidence.
Passing guarded CI, unassisted Intel tests or the non-voting reproducer cannot
close this separate obligation. See the [roadmap](../roadmap.md).
