# Sample Lifecycle Alpha Release Readiness

Date: 2026-09-08

Final release-candidate status: **NO-GO**

All current automated, optimized-build, source-preservation, persistence,
hygiene, agent-driven GUI, and mandatory current-build maintainer
musician/listening gates pass. During final manual acceptance, however, Gregory
reproduced a destructive document-replacement defect: File > New / Cmd+N
immediately replaced a non-pristine editable composition without warning and
left no Undo recovery. This direct evidence promotes the previously audited
VTX-G-003 data-loss finding to a release blocker for this candidate.

## Current audited candidate

- Branch: `release/sample-lifecycle-alpha-final-gate`
- Audited `main`: `4df4258cd61dc7a7b976d2b3febfc7874f70bbb4`
- Local `main` and `origin/main` were synchronized at `0 0`, with a clean worktree,
  before this branch was created.
- The candidate includes the J-003 navigation remediation from PR #399, explicit
  editable-copy planning from PR #400, and normalized editable-copy UI from
  PR #401.
- This gate changes no production source, supported file format, compatibility
  boundary, runtime backend, or version. It creates no tag or published release.
- The independent cross-family audit is frozen and unchanged.

## Current gate results

| Area | Result |
| --- | --- |
| J-003 empty patterns | Pass. A new document exposed blank allocated P000, P001, and P002 in both the main PTN popup and Pattern Bank before events were added. ORD000/001/002 displayed their respective blank patterns. |
| J-003 stopped navigation | Pass. POS/PTN traversed `0/000 -> 1/001 -> 2/002 -> 1/001 -> 0/000`, with main presentation and Song/Order selection agreeing. |
| J-003 view/play separation | Pass. At POS1, viewing P000 kept the order at P001; normal Play started POS1/P001, while Play Current Pattern started P000. A harmless instrument edit and immediate Undo/Redo caused no navigation snap-back. |
| J-003 live follow | Pass. Distinct P000/P001/P002 content followed live as `00/000 -> 01/001 -> 02/002`; the tracker followed and Stop reconciled once to the final playback position. |
| Loaded-XM navigation | Pass. The public generated multi-pattern/order fixture traversed and followed live through `0/000`, `1/001`, and `2/002`, then reconciled correctly on Stop. |
| Exact editable copy | Pass. The stopped command transitioned immediately with no normalization warning, left the source unchanged, and produced a supported export whose reopen/re-export was byte-identical. |
| Normalized Profile v1 copy | Pass. A deterministic public-safe synthetic Linear XM with one referenced noncanonical zero-payload empty header transitioned immediately without pre-confirmation. The informational disclosure accurately described normalization and did not claim lossless or byte-identical conversion. |
| Normalized state preservation | Pass. Required empty S02 identity and its 96-note reference were preserved as an unavailable/silent route, no PCM was fabricated, and the original source remained unchanged. Export/reopen/re-export preserved the normalized editable semantics and produced identical canonical exports. |
| Unavailable reasons | Pass. Amiga frequency mode and an invalid represented loop state each produced a specific explanatory sheet, no editable transition, and no source mutation. Invocation during playback was inert and command behavior returned after Stop. |
| Sample Lifecycle | Pass. Clear, exact-slot repopulation, Duplicate, Move, both Swap forms, and Undo/Redo retain canonical map/routing semantics in full automated coverage. Agent GUI checks confirmed Clear/Undo/Redo/repopulate/Duplicate/Move focus and refresh behavior. |
| Clear Song Data | Pass. Both entry points shared confirmation; Cancel was safe, Confirm cleared only patterns/orders, instruments and samples remained, and immediate Undo/Redo was exact. Loaded-source behavior remains unchanged. |
| Audio-export re-entry | Automated and maintainer pass. All WAV-active/M4A-active cross-command combinations reject re-entry without a second picker, sheet, token, or job, and all terminal paths restore availability. Gregory's long WAV and M4A checks passed. |
| XM persistence | Pass. A composed lifecycle document retained two patterns/orders, instrument/sample identities, sparse S02, represented S01/S03 PCM and loop metadata, and the full S03 note map after export, reopen, editable copy, and deterministic re-export. |
| Maintainer musician/UI/listening | Pass. The current-main from-scratch navigation, live follow, lifecycle routing, Clear Song Data, exact/normalized/unavailable editable-copy, normalized export/reopen, long audio-export re-entry, and persistence/listening checks passed. |
| Document replacement safety | **BLOCKER.** File > New / Cmd+N silently discarded a non-pristine editable composition and its recovery history. VTX-G-003 establishes the same class for a successful File > Open / Cmd+O. |

### Loaded-source and persistence checksums

- The manifest-pinned public multi-order source remained
  `8438e6074df6d4a6e1ec540121b7adeaf96e199166619a0ae00085c7fafd1ca3`.
- The exact-copy export and its re-export were identical at
  `72dcbb7ed377a804bfd0f0128ed77ee073e60fadaad21f40e0e49abd8f7e18b0`.
- The normalized source remained
  `a9baa66980a7fd9a6ff2772063c691d0c5b711b813389d26304fa8f9564b0e77`;
  its canonical export and re-export were identical at
  `43daeaf6daf50dcb3640ba0605f0fa793f31949454cf17a659af7f9911e86e24`.
- The composed lifecycle export and re-export were identical at
  `60aea0ce8530d929e151cba49cb603d8ca4571fb0d5d728beeb9a4fcc9015553`.
- Original-to-export byte parity is intentionally not claimed for normalized
  legacy input; the comparison is normalized editable state versus reopened
  normalized export.

## Current automated and build verification

| Command / gate | Result |
| --- | --- |
| `python3 scripts/generate-synthetic-xm-fixtures.py --verify` | Pass; 5 fixtures verified byte-identically. |
| `swift test --filter ModuleCoreTests` | Pass; 24 tests, 0 failures. |
| `swift test --filter VTXRenderBoundedXMTests` | Pass; 117 tests, 0 failures. |
| `swift test` | Pass; 141 tests, 0 failures. |
| Full Debug `xcodebuild ... test` | Pass; 1,540 tests, 0 failures, 0 skipped. |
| `./scripts/check-files.sh` | Pass. |
| `./scripts/scan-tracked-private-leaks.sh` | Pass. |
| `python3 -m unittest discover -s tools -p '*_tests.py'` | Pass; 222 tests, 0 failures. |
| `git diff --check` | Pass before the report update; rerun in final hygiene. |

All Xcode test/build commands used exactly `-derivedDataPath build` and ran in
the required order: Debug tests, host Release, universal Release, then the final
canonical Debug rebuild. No gate-specific repository build directory was made.

| Build | Result | Executable architecture |
| --- | --- | --- |
| Host Release, `platform=macOS` | `BUILD SUCCEEDED` | `x86_64`, confirmed by `file` and `lipo -archs`. |
| Universal Release, `generic/platform=macOS`, `ARCHS="arm64 x86_64"` | `BUILD SUCCEEDED` | `x86_64 arm64`, confirmed by `file`, `lipo -archs`, and local `lipo <executable> -verify_arch arm64 x86_64`. |
| Final maintainer-facing Debug | `BUILD SUCCEEDED` | Canonical app rebuilt under `build/Build/Products/Debug/VoodooTrackerX.app`. |

The task prompt's operand-first `lipo -verify_arch arm64 x86_64 <executable>`
form is not accepted by the installed `lipo`; its equivalent local path-first
form returned success for both required architectures. Release builds emitted
only the expected App Intents metadata warning. The Swift 6.3.2
`@_optimize(none)` workaround remains on `SampleEditorView.buildParams`.

## Current agent-driven GUI evidence

Temporary screenshots and generated fixtures were kept outside the repository.
They provide non-auditory evidence only and do not replace maintainer listening.

- A fresh editable document showed the three allocated empty patterns, aligned
  gutter/body geometry, a static highlight row, correct wrap/follow behavior,
  and no phantom rows. Stopped and live J-003 results matched the matrix above.
- The exact-copy path used the public generated multi-order fixture. Loaded
  navigation remained correct before conversion, conversion required no warning,
  and source bytes remained unchanged.
- The normalized Profile v1 path displayed S02 as `Empty destination`, retained
  its mapped ownership segment as unavailable, and showed no represented sample
  or fabricated PCM. Its post-transition disclosure explicitly warned that an
  exported file may differ structurally from the original.
- The unavailable Amiga and represented-loop cases gave actionable, typed
  reasons while preserving the loaded source and read-only state.
- Clearing mapped S01 left all 96 references routed to the now-unavailable S01;
  Undo restored the represented sample, Redo removed it again, and deterministic
  repopulation restored the same identity. Duplicate selected the new identity;
  Move selected its destination and remapped note ownership to preserve content.
- Direct Sample Editor audition targeted the selected represented sample and
  returned to its stopped UI state. No human-ear quality claim is made.
- Clear Song Data from both Edit and Song/Order retained the sample palette,
  reset to one empty P000/ORD000 on Confirm, and restored the prior two-order
  document on Undo.
- The composed lifecycle XM reopened with S01 and S03 represented, S02 empty,
  and the complete 96-note map still targeting S03. Its re-export matched.

## Current maintainer musician/UI/listening evidence

Gregory completed the mandatory checklist in the canonical rebuilt Debug app.
The following current-main evidence passed:

- From-scratch three-sample mapping, P000/P001/P002 and ORD000/001/002 creation,
  blank-pattern visibility, stopped navigation, and live POS/PTN/tracker follow.
- Audible Clear, Undo, exact-slot repopulation, Move or Swap, and Undo/Redo
  routing semantics with distinguishable sample identities.
- Clear Song Data Cancel, Confirm, and Undo behavior.
- Exact, normalized Profile v1, and unavailable editable-copy behavior. The
  normalized disclosure was accurate, the source stayed untouched, and its
  export/reopen result remained musically and semantically correct.
- Long WAV and M4A export re-entry behavior, including cross-command exclusion,
  no second destination chooser, and restoration after cancellation/completion.
- Final XM persistence and listening sanity, including export, reopen, editable
  copy where applicable, and subsequent listening.

These passes close the prior CONDITIONAL GO evidence gap. They do not override
the separately reproduced destructive document-replacement blocker below.

## Release blocker: VTX-G-003

Gregory reproduced this current-main sequence during final manual acceptance:

```text
non-pristine editable composition
-> File > New / Cmd+N
-> immediate replacement with a new blank document
-> no warning
-> no Undo recovery
```

This is VTX-G-003,
`G-mutation-defense:new-open-discard-unsaved-document-without-confirmation`,
which the frozen independent audit already classified as a confirmed supported-
workflow data-loss defect. The live final-gate reproduction promotes its release
disposition from scheduled MEDIUM debt to a blocker for this candidate; the
frozen report itself remains unchanged.

The same audited class applies to File > Open / Cmd+O after a module is selected
and successfully loaded: the current editable document and its undo history are
replaced without a dirty-document confirmation. Canceling the file chooser or a
failed load does not reproduce that successful-open replacement path, but those
defenses do not protect a completed Open action.

Save and Save As remain intentionally deferred; their absence raises the impact
because Export XM is the only persistence route, but pulling them forward is not
the correct release fix. The narrow remediation is a destructive-document-
replacement confirmation guard, backed by dirty-state handling, for New and
successful Open, with Cancel preserving the complete document and Undo history.

## Packaging, privacy, and read-only checks

- No custom placeholder app icon is bundled or declared; the built app uses
  default macOS icon behavior, while the separate VTX logo renders normally.
- Loaded sources remained read-only. Save and Save As stayed disabled; supported
  editable copies exposed Export XM without mutating the source.
- Repository private-leak and file checks pass. No private corpus name/path,
  generated WAV/M4A/XM, screenshot, trace, log, or new third-party asset is
  tracked by this gate.
- All local gate artifacts remained temporary and untracked. Existing unrelated
  ignored build material was not modified or removed as part of the gate.

## Accepted post-alpha findings

| Finding | Current disposition |
| --- | --- |
| VTX-CS-001 | Accepted HIGH: Fxx timing-planner mismatch; focused post-alpha playback work. |
| VTX-CS-002 | Accepted HIGH: portamento scale mismatch; focused post-alpha playback work. |
| VTX-D1-001 | Accepted HIGH: CoreAudio callback allocation / real-time-safety debt; focused post-alpha real-time work. |

No current gate evidence changes their accepted post-alpha scope or promotes
them to Sample Lifecycle release blockers.

## Current verdict and release action

The candidate is **NO-GO** because VTX-G-003 permits routine New and successful
Open actions to destroy unexported editable work without warning or recovery.
All other machine and maintainer gates passed. `v0.3.0-alpha.2` is not authorized,
and no tag or release was created. Remediation belongs in one focused VTX-G-003
New/Open discard-confirmation PR from synchronized `main`, not in this gate and
not through an expansion into Save/Save As.

---

## Superseded final-gate evidence (2026-09-05)

The following prior candidate record is retained for chronology. Its NO-GO was
based on the then-live J-003 reproduction and is superseded by the current
audited candidate and passing remediation evidence above.

## Final release-candidate audited base

- Branch: `release/sample-lifecycle-alpha-final-gate`
- Final audited `main`: `fba3d7b05d178f92a0e398e56d578d6277bb36bf`
- Local `main` and `origin/main` were synchronized at `0 0` before the branch
  was created, and the working tree was clean.
- PR #397, `docs/sample-lifecycle-alpha-release-reconciliation`, is merged at
  the audited commit.
- The independent cross-family audit remains frozen and unchanged. Its 0
  BLOCKER result and manager-approved remediation/deferral decisions are
  summarized in the
  [audit disposition](sample-lifecycle-alpha-cross-family-audit-disposition.md).
- This gate changes no production source, file format, parser/writer behavior,
  runtime backend, or release version. It creates no tag or published release.

## Post-audit remediation reconciliation

| Finding | Final release-candidate state |
| --- | --- |
| VTX-F-001 | Remediated by PR #392 (`de362366`): one shared in-flight presentation gate covers WAV and M4A. |
| VTX-G-001 / VTX-G-002 | Remediated by PR #393 (`f72cb43`): both Clear Song Data entry points share stopped-state, confirmation, stale-state, and one-edit Undo/Redo behavior. |
| VTX-A1-002 | Remediated by PR #394 (`dc2d40d`): Clear Sample promises only immediate Edit > Undo. |
| Targeted VTX-L-001 portion | Remediated by PR #395 (`b82f703`): the contradictory selector spec was removed and the cursor-outline test uses production geometry. |
| VTX-CS-003 | Remediated by PR #396 (`a2a703d`): the third-party-derived placeholder app icon and all build references were removed. |

No accepted remediation was reopened or silently broadened in this gate.

## Final automated and build verification

| Command / gate | Final result |
| --- | --- |
| `python3 scripts/generate-synthetic-xm-fixtures.py --verify` | Pass; 5 fixtures verified byte-identically. |
| `swift test --filter ModuleCoreTests` | Pass; 24 tests, 0 failures. |
| `swift test --filter VTXRenderBoundedXMTests` | Pass; 117 tests, 0 failures. |
| `swift test` | Pass; 141 tests, 0 failures. |
| Full Debug `xcodebuild ... test` from the final-gate prompt | Pass; 1,505 tests, 0 failures, 0 skipped. |
| Focused final composed lifecycle test after chain-order strengthening | Pass; 1 test, 0 failures. |
| `./scripts/check-files.sh` | Pass. |
| `./scripts/scan-tracked-private-leaks.sh` | Pass. |
| `python3 -m unittest discover -s tools -p '*_tests.py'` | Pass; 222 tests, 0 failures. |
| `git diff --check` | Pass. |

No additional release-gate script exists in `scripts/`; the current repository
checks named above are the applicable release gates.

Clean optimized build results:

| Build | Result | Executable architecture |
| --- | --- | --- |
| Host Release, `platform=macOS` | `BUILD SUCCEEDED` | `x86_64` confirmed by `file` and `lipo -archs`. |
| Universal Release, `generic/platform=macOS`, `ARCHS="arm64 x86_64"` | `BUILD SUCCEEDED` | `x86_64 arm64` confirmed by `file`, `lipo -archs`, and an explicit `lipo -verify_arch arm64 x86_64` assertion. |

Both Release builds emitted only the expected App Intents metadata warning
because the app has no AppIntents dependency. The Debug test build also emitted
one existing test-only Sendable-capture warning in
`InstrumentEditorWindowControllerTests`. The Swift 6.3.2
`@_optimize(none)` workaround remains on `SampleEditorView.buildParams`.

## Current maintainer musician workflow evidence

Gregory exercised the current release-candidate build after the technical gate.
The following lifecycle and routing observations passed:

- He added three instruments; all three mapped and played correctly.
- He created multiple patterns and orders.
- Clearing a mapped represented sample in Sample Editor changed that exact row
  to `Empty destination`. The keymap reference to the sample identity remained,
  so its previously routed note became honestly unavailable/silent rather than
  being remapped.
- Undo restored the represented sample content and its audible route.
- Other Sample Lifecycle operations exercised in the session behaved correctly
  unless explicitly identified below.

Two observations are potentially confusing UX, not correctness defects under
the current documented and tested contracts:

- Order Ops `INSERT` inserts after the selected order and uses that selected
  order slot's existing pattern reference. It does not implicitly use the
  Pattern Bank's viewed pattern; assigning a Pattern Bank pattern remains an
  explicit operation. No INSERT semantic change belongs in this gate.
- Main-selector or Pattern Bank single-click selection is view-only. Normal
  `Play` starts from the selected POS/order and its pattern reference, while
  `Play Current Pattern` starts the displayed pattern from row 0. Viewing
  pattern `000` while the selected order references pattern `001` therefore
  does not make normal Play start pattern `000`. The distinction may deserve
  future UX clarification, but it is not this release blocker.

### Release-blocking POS/order navigation reproduction

After creating multiple patterns and orders, Gregory observed that the
main-window POS up/down control did not update the visible position number as
expected. He could not reliably navigate back to order position `0`. The
selected/current order, main POS presentation, displayed pattern, and normal
Play start behavior no longer appeared to agree.

This is a headline supported multi-order composition workflow, so the live
reproduction invalidates this release candidate even though no data loss was
reported. It directly correlates with frozen audit finding VTX-J-003,
`J-architecture-drift:editable-view-position-dual-truth`: editable navigation
is split between `BlankTrackerDocument.currentPosition/currentPatternIndex`
and the `AppDelegate` mirrors `selectedSongPositionIndex`,
`currentPatternIndex`, and `selectedPatternSelectionIndex`. The audit traced the
main song-position stepper as a mirror-only write while blank-document control
panel synchronization can re-drive visible POS from the document's stale
`currentPosition`.

The independent audit remains unchanged at MEDIUM, reflecting the static
evidence and non-blocking disposition available when it was written. This gate
does not retroactively alter that severity; it promotes VTX-J-003 to a release
blocker for this candidate because current-build maintainer evidence now
demonstrates the failure in supported use.

Required remediation:

```text
one focused J-003 editable song-position/navigation authority PR
-> rerun relevant musician multi-order workflow
-> rerun final release gate on the new main
```

The remaining live long-export WAV/M4A re-entry condition was not required to
be completed after this release blocker was found, and no current-build human
pass is claimed for it.

## Final lifecycle composition and XM persistence evidence

The strengthened
`testSampleLifecycleMilestoneGateComposesActionsAndRoundTripsSupportedState`
now follows the final gate's required action order on one deterministic editable
document:

```text
S01 Low Pulse / S02 High Ramp / S03 Impulse with three exact map regions
-> Clear mapped S02 -> unavailable route -> Undo/Redo
-> populate exact empty S02 with Replacement -> route restored -> Undo/Redo
-> Duplicate S01 to tail S04 with map unchanged -> Undo/Redo
-> Move S04 to S01 with routing and selection preserved -> Undo/Redo
-> Swap represented/represented with routing preserved -> Undo/Redo
-> Clear Replacement and Swap represented/empty
-> unavailable route preserved without fabrication -> Undo/Redo
-> Export XM -> reopen -> Make Editable Copy -> deterministic re-export
```

The test compares exact represented identities, the complete 96-entry map,
selection, distinguishable PCM and sample metadata, volume/panning envelopes,
fadeout, autovibrato, patterns/events, orders, restart position, speed, and BPM.
Pattern cells remain instrument identities. Every sample-slot operation leaves
song/order/pattern data unchanged, selection changes do not change mapped
routing, and direct Sample Editor audition still targets the selected sample.
The final sparse export reopens with exact canonical empty-slot provenance,
becomes an editable copy, and re-exports byte-identically. Focused dense/sparse
Move, both Swap forms, malformed/state-D, cancel, same-slot, stale, read-only,
playing, failure, and no-op tests provide the zero-history defenses without
duplicating them in the composed test.

Result by lifecycle action:

| Action | Result |
| --- | --- |
| Clear | Pass; exact S02 removal, unchanged map/song, unavailable mapped route, one exact Undo/Redo. |
| Repopulate | Pass; exact empty S02 receives replacement content, unchanged map/song, route becomes available, one exact Undo/Redo. |
| Duplicate | Pass; independent S04 tail identity, no hole filling or auto-map, selection follows the copy, one exact Undo/Redo. |
| Move | Pass; insertion semantics transform identities/map/selection together and preserve note-to-content semantics. |
| Swap represented/represented | Pass; pairwise exchange preserves note-to-content semantics and selection. |
| Swap represented/empty | Pass; no sample is fabricated and the previously unavailable route stays unavailable. |

## Clear Song Data final regression evidence

- Both `Edit > Clear Song Data` and `Song / Order Editor > CLEAR SONG` invoked
  the same native editable-document confirmation in the GUI smoke.
- Cancel left the document and existing Undo title unchanged.
- Model/coordinator tests prove stopped-only gating, pattern/order-only clearing,
  palette preservation, exactly one `Clear Song Data` edit, exact immediate
  Undo/Redo, and zero history for no-op, playing, unavailable, stale, and
  conflicting-presentation paths.
- The public-fixture loaded-module smoke showed source-specific confirmation
  copy stating that the loaded module remains unchanged. Cancel preserved the
  source, and focused tests prove that Confirm creates exactly one cleared
  editable copy while retaining the original loaded value.
- The public fixture's SHA-256 remained the manifest-pinned value after the
  smoke. VTX-J-002 remains untouched and out of scope.

## Audio-export presentation evidence

All eight `AudioExportPresentationGateTests` pass. They pin the full matrix:

```text
WAV active -> WAV disabled
WAV active -> M4A disabled
M4A active -> WAV disabled
M4A active -> M4A disabled
```

The same tests prove that stale/direct invocation creates no second destination
picker, token, sheet, or export job; an active sheet is not replaced; and
success, failure, or cancellation restores both commands exactly once. Playing
and unavailable-document defenses remain unchanged. The live long-export menu
check was not completed after the POS/navigation release blocker was found and
is not claimed from automated evidence.

## Read-only, editor, tracker, preview, and packaging smoke

A fresh Debug app launch completed without a startup crash or missing-resource
warning. Non-auditory screenshots and temporary notes remain outside git.

- Sample Editor: canonical empty S01 showed no represented metadata, enabled
  LOAD/SINE, and disabled direct audition/Clear. Generated S01 showed exact
  waveform/metadata, enabled direct audition/Clear and lifecycle commands, and
  used the truthful Clear warning. Clear, Cancel, Undo, Redo, repopulation, and
  Duplicate refreshed the shared presentation correctly.
- Instrument Editor: S01/S02 rows tracked the shared selection. After Duplicate
  selected S02, the visible ownership strip remained all S01, confirming that
  selected sample is editing focus and the 96-note map remains routing
  authority. Automated UI tests cover Move/Swap refresh of rows, metadata,
  ownership, selection, preview release, and empty-destination mutator gating.
- Song / Order Editor: both Clear Song entry points displayed the same
  confirmation; Cancel was non-mutating. During playback, lifecycle, pattern,
  order, metadata, and Clear Song mutations were disabled while direct preview
  remained transport-independent.
- Loaded/read-only: lifecycle mutations, Save, Save As, and Export XM were
  disabled; Make Editable Copy was explicit. After the supported copy, Export
  XM became available while Save and Save As remained disabled.
- Tracker: Home placed row `00` on the unchanged static highlight with blank
  slots above; End placed `3F` on the same highlight with blank space below;
  Down and Up wrapped between them without moving the anchor. Gutter/body rows
  were visually aligned, no phantom rows appeared, the selector displayed
  zero-padded decimal `000`, and the cursor retained its red outline. Full
  viewport and playback-follow tests also pass. Those checks do not cover the
  newly reproduced multi-order POS/navigation authority failure.
- Preview/audio: automated suites pass direct Sample versus keymap-driven
  Instrument/tracker routing, persistent-stream reuse, stale-preview
  cancellation, no auto-audition after lifecycle/Undo/Redo, and transport
  isolation. No human-ear claim is made by Codex.
- App icon: no app-icon build setting, bundle declaration, custom icon resource,
  or removed `vtx-icon` asset is present. The built bundle contains the separate
  VTX logo resources, the logo panel rendered normally, and the app launched
  with default macOS icon behavior. No replacement icon was introduced.

## Final documentation and privacy consistency

`README.md`, both roadmaps, `docs/agent-current-state.md`, this report, and the
audit disposition consistently describe `v0.3.0-alpha.1` as shipped, current
Sample Lifecycle operations as implemented, Move Up/Down convenience and other
deferred directions as deferred, the three accepted HIGH findings as
post-alpha work, and final release gating as the current action. The frozen
independent audit report is untouched.

The tracked-private/artifact scan passes. No private module or corpus name,
machine-specific home path, generated audio/XM/screenshot/trace/log, new
third-party visual asset, or unapproved tracker fixture was added. Gate media,
logs, Xcode results, and derived data are temporary and untracked.

## Accepted post-alpha findings

| Finding | Final disposition |
| --- | --- |
| VTX-CS-001 | Accepted HIGH: Fxx timing-planner mismatch; focused post-alpha playback work. |
| VTX-CS-002 | Accepted HIGH: portamento scale mismatch; focused post-alpha playback work. |
| VTX-D1-001 | Accepted HIGH: CoreAudio callback allocation / real-time-safety debt; focused post-alpha real-time work. |

No final-gate evidence shows that these accepted findings break Sample Lifecycle
scope, so they are not promoted to release blockers.

---

## Historical internal gate evidence (2026-09-02)

## Audited base and entry condition

- Branch: `release/sample-lifecycle-alpha-gate`
- Audited `main`: `647dbfcc691f9d7edc73276fada9bc13b93e3db3`
- Local `main` and `origin/main` were synchronized at `0 0` before the branch
  was created.
- PR #389, `sample/swap-represented-sample-with-slot-ui`, is merged at the
  audited commit and its `macos-checks` result is successful.
- At session start, PR #389 had no formal review and left maintainer listening
  unchecked. Before submission, the maintainer attested that every current
  musician/listening/UI gate item passed, with no failed reproduction.

## Scope and capability boundary

This gate adds no capability and changes no production source. It audits the
already-merged Sample Lifecycle Alpha surface and adds one test-only composed
lifecycle/persistence scenario. The supported boundary remains:

- Sample identities are S01...S16 at the UI and zero-based internally.
- Clear removes one represented sample in place; exact empty-destination
  population restores that identity; Duplicate appends at the tail.
- Move has insertion/shift semantics. Swap exchanges two exact identities,
  including a represented/empty pair.
- Lifecycle mutation is stopped-editable-only and commits through one shared
  document edit/Undo boundary.
- Loaded modules remain read-only. Supported stopped XM files become mutable
  only through Make Editable Copy.
- Save and Save As remain disabled; Export XM remains the persistence route.
- No XM format, parser compatibility, runtime mixer, or tracker viewport
  behavior changed in this gate.

## Audited invariants

- Represented sample values retain PCM and metadata while identities move.
- Every lifecycle permutation applies one bijection to represented indices,
  all 96 map entries, and represented or empty selection.
- Empty mapped identities remain honestly unavailable; no first-playable
  fallback leaks into canonical lifecycle operations.
- Selected sample is editing focus, not routing state.
- Sample Editor preview resolves the exact selected sample directly, while
  Instrument Editor, pattern preview, live playback, and offline render resolve
  the instrument's note map.
- Patterns retain instrument references and never participate in sample-slot
  permutation.
- Success creates exactly one labeled document edit; cancel, stale, malformed,
  read-only, playing, same-slot, and no-op paths create no mutation or history.
- Sparse XM placeholders are canonical all-zero 40-byte headers and are accepted
  for editable copy only with exact source provenance.

## Lifecycle matrix

| Scenario | Required observable | Evidence | Result |
| --- | --- | --- | --- |
| Clear | Remove exact represented identity; preserve map, later samples, patterns, selection; one Undo/Redo | Composed gate test; `testClearSelectedRepresentedSampleRemovesOnlyExactIdentityWithoutCompactingOrRemapping`; coordinator Clear tests | Pass |
| Exact empty repopulation | Populate captured empty Sxx without compaction or remap; restore route; one Undo/Redo | Composed gate test; `testAudioImportPopulatesSelectedInteriorEmptyIdentityWithoutRenumberingOrRemapping`; coordinator population tests | Pass |
| Duplicate | Deep-copy to tail, leave sparse hole and 96-map unchanged, select copy; one Undo/Redo | Composed gate test; `testDuplicateSelectedRepresentedSampleDeepCopiesToTailWithoutFillingSparseHoleOrChangingMap` | Pass |
| Dense Move | Shift represented identities and exact 96-map together; preserve resolved content identity, patterns, and selection; one Undo/Redo | Composed gate test asserts map `1/2/3`; `testSampleSlotPermutationTransactionPreservesDenseSparseMoveAndSwapSemantics` | Pass |
| Sparse Move | For S01=A, S02=empty, S03=C, moving C to S02 preserves C and moves unavailable route to S03 | Composed gate test asserts map `0/2/1`; `testMoveSampleUISparseMoveIntoEmptyPreservesUnavailableRouteAndUndoRedo` | Pass |
| Represented Swap | Exchange two represented identities and map values without changing resolved sample identity | Composed gate test asserts map `1/2/0`; coordinator Swap test | Pass |
| Represented/empty Swap | Move content and unavailable identity pairwise without fabrication or fallback | Composed gate test asserts final map `1/0/2`; represented-empty coordinator test | Pass |
| Selection independence | Changing selected sample does not change mapped resolution; direct Sample audition still targets the selection | Composed gate test; Sample/Instrument audition and keymap-assignment tests | Pass |
| Defenses | State D, malformed maps, stale modal context, read-only, playing, cancel, and same-slot remain no-edit | Permutation rejection tests and Sample Editor modal/import tests | Pass |

The composed test is
`testSampleLifecycleMilestoneGateComposesActionsAndRoundTripsSupportedState`
in `EditableXMWriterTests.swift`. It runs all lifecycle action classes through
one coordinator/history sequence. The final release gate later reordered that
same test to match the required Clear -> repopulate -> Duplicate chain; sparse
Move remains covered by its focused coordinator/UI tests.

## Persistence and semantic round-trip

The composed final sparse document performs:

`lifecycle operations -> Export XM bytes -> reopen -> Make Editable Copy -> re-export`

The following are compared exactly:

| State family | Exact comparison |
| --- | --- |
| Identity | Instrument identities, sample identities, sparse gap, 96-entry map |
| Sample | PCM, name, volume, panning, relative note, finetune, bit depth, loop start/length/type |
| Instrument | Name, volume envelope including fadeout, panning envelope, autovibrato |
| Song | Patterns/events, channel shape, order table, restart position, speed, BPM |
| Copy/export | Reopened instrument palette equals the final document; editable copy equals it; re-export is byte-identical |

The test uses three distinct I01 samples, a separate I02 sample, three mapped
note regions, two patterns, two orders, non-default restart/BPM, envelopes,
fadeout, autovibrato, mixed sample metadata, and distinguishable PCM. The final
reopen records the exact canonical empty source header before Make Editable Copy.

## Writer, provenance, and atomic safety

- `testDenseAlpha1OutputRemainsByteIdentical` pins the unchanged dense writer
  result.
- `testSparseInteriorGapWritesCanonicalPlaceholderAndReopensExactIdentityAndMap`
  pins canonical sparse headers, payload ordering, identities, map, and routing.
- `testNoncanonicalZeroLengthSourceHeadersRemainUnavailableForEditableCopy`
  rejects named or metadata-bearing zero-length source headers.
- The composed test proves deterministic writer output, semantic reopen,
  supported editable-copy recovery, and byte-identical re-export.
- The composed test sends both export and re-export through
  `ExportXMCoordinator` and compares both destination files with the canonical
  writer bytes. Companion coordinator tests cover valid replacement,
  map/writer/payload failure, and preservation of an existing destination.

No writer, parser, source-provenance, or atomicity regression was found.

## Automated verification

| Command | Result |
| --- | --- |
| `python3 scripts/generate-synthetic-xm-fixtures.py --verify` | Pass; 5 fixtures verified byte-identically |
| `swift test --filter VTXRenderBoundedXMTests` | Pass; 117 tests, 0 failures |
| `swift test --filter ModuleCoreTests` | Pass; 24 tests, 0 failures |
| `swift test` | Pass; 141 tests, 0 failures |
| Full Debug `xcodebuild ... test` command from the gate prompt | Pass; 1,487 tests, 0 failures |
| Final focused composed lifecycle test | Pass after exact-map oracle strengthening |
| `./scripts/check-files.sh` | Pass |
| `./scripts/scan-tracked-private-leaks.sh` | Pass |
| Explicit intended-file private-name/path scan | Pass; no match |
| `python3 -m unittest discover -s tools -p '*_tests.py'` | Pass; 222 tests |
| `git diff --check` | Pass |

## Optimized build evidence

| Build | Result | Executable architecture |
| --- | --- | --- |
| Clean host Release, `build-release` | `BUILD SUCCEEDED` | `x86_64` |
| Clean generic macOS Release with `ARCHS='arm64 x86_64'`, `ONLY_ACTIVE_ARCH=NO`, `build-release-universal` | `BUILD SUCCEEDED` | `x86_64 arm64` confirmed by both `file` and `lipo -archs` |

The only observed build warning was App Intents metadata extraction being skipped
because the app has no AppIntents dependency.

## Tracker and preview regression reconciliation

The full suite passed static-anchor, shared-slot, wrap, no-phantom-tail,
gutter/body-Y, and playback-follow model tests. Preview suites passed direct/map
routing, generation-safe cancellation, persistent-stream reuse, loaded/read-only
and idle/running gating, and controller/router reopen coverage. Maintainer
validation subsequently passed final AppKit and observed transport behavior.

## Human musician and UI gate

Status: passed by maintainer attestation on 2026-09-02. Codex did not perform or
claim listening evidence. Its separate non-auditory launch smoke showed a clean
blank tracker without a startup crash; the screenshot remains under `/tmp`.
No failed maintainer reproduction was reported.

Maintainer musician checklist:

- [x] From File > New, create/import/generate and play a short piece with two
  instruments, three distinct samples, mapped regions, and multiple patterns/orders.
- [x] Audition each selected identity directly; change selection and verify
  mapped notes do not change.
- [x] Exercise Clear and verify unavailability; Undo restores sound and Redo
  removes it again.
- [x] Repopulate the exact empty identity and verify routing returns.
- [x] Exercise Duplicate; directly audition the independent appended copy and confirm no auto-map.
- [x] Exercise dense/sparse Move and both Swap forms; confirm sound or honest
  unavailability follows, then confirm representative Undo/Redo.
- [x] Play the composition, Export XM, reopen, and compare musical behavior.
- [x] Make Editable Copy, repeat lifecycle/preview checks, Export XM plus WAV/M4A,
  reopen the re-exported XM, and compare again.

Maintainer UI smoke checklist:

- [x] I01/I02 and S01/S02/S03 rows, including empty versus unnamed, remain
  truthful across all shared surfaces.
- [x] LOAD/SINE/Clear/Duplicate/Move/Swap enable in the correct mapped/unmapped context;
  Save and Save As remain disabled.
- [x] Clear names the target and mapped-note warning; Cancel is mutation-free.
- [x] Move/Swap sheets attach to the main tracker window, describe insertion or
  exchange semantics, and Cancel creates no mutation or Undo entry.
- [x] MAP RANGE and ownership remain instrument-driven and read-only display is
  truthful.
- [x] Loaded/read-only, editable-copy, and playing states remain selectable but
  lifecycle mutation remains correctly gated.
- [x] Stale sheet confirmation is rejected without history.
- [x] Red close and Command-W release preview and reopening creates one fresh
  controller/router.
- [x] Lifecycle actions cancel preview; Instrument remains map-driven, Sample direct, selection does not reroute, and Play/Stop state is unchanged.
- [x] Tracker anchor, gutter/body alignment, top/bottom wrap, playback-follow,
  and absence of early phantom rows remain visually correct.

## Known limitations and evidence boundaries

- The predecessor PR has no formal review recorded, although it is merged and
  CI-green; the current maintainer gate revalidated its listening/UI surface.
- Human evidence is a pass/fail maintainer attestation; no media is tracked.
- Tracker viewport tests cover a mirrored test geometry, not final AppKit glyph
  placement; runtime follow tests stop before the rendered AppDelegate path.
- Sheet parentage, red-close/Command-W behavior, preview/transport isolation,
  and actual audio identity were passed by the maintainer rather than inferred
  from unit tests.
- No new fixture, private module, screenshot, trace, or audio artifact is tracked.

## Historical file and artifact audit

- At that internal gate, intended changes were one app integration test, this
  report, and concise status pointers in `docs/agent-current-state.md` and
  `docs/roadmap.md`.
- Production source and on-disk formats are unchanged.
- Build outputs stayed out of tracked files; universal derived data, logs, and
  the launch screenshot remain under `/tmp`.
- No tag or release was created. The gate changes remain uncommitted as required.

## Historical internal gate verdict — GO

No reproducible correctness blocker was found. Automated, optimized-build, and
repository-hygiene gates passed, and the maintainer reported every required
musician/listening/UI item passed on the audited milestone.

At that internal gate, the branch was ready for the independent cross-family
read-only audit before the next alpha tag.

The historical handoff was to request the independent cross-family read-only
audit before the next alpha tag; that audit is now complete.

## Final release-candidate verdict — NO-GO

The automated suites, exact Sample Lifecycle persistence checks,
host/universal builds, repository hygiene, and recorded lifecycle/routing
observations pass. The current-build maintainer reproduction of inconsistent
multi-order POS/navigation invalidates the release candidate and promotes
VTX-J-003 to a blocker for this candidate. The release gate must be rerun after
a separately scoped fix lands on `main`.

Candidate version recommendation only: `v0.3.0-alpha.2`. It is not ready or
authorized for tagging, and this gate creates no tag or release.

Recommended next action: maintainer review/merge this truthful failed-gate
report/test PR, then start one focused VTX-J-003 editable song-position
authority fix from synchronized main.
