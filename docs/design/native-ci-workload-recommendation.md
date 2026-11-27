# Native CI workload policy

The `issue516-loop-native` workflow always creates its `continuation` job named
**Loop continuation arm64 ASan and Release** for PRs targeting main. Classification
happens inside that job; there are no workflow path filters or job-level skips.
Ordinary checks and ROWSTACK1 remain unchanged. No branch protection is modified.

| Change or event | Native workload |
| --- | --- |
| Only `README.md` or canonical `docs/**/*.md` paths | `NATIVE_NOT_REQUIRED` after verified complete PR-file acquisition; only the expensive step is skipped. No native tests are claimed. |
| App, core/parser/mixer, tests/fixtures, packages, `.github`, classifier/tests, scripts, tooling, artwork, configuration or any other path | Full qualification. Markdown outside the explicit allowlist also requires full qualification. |
| Mixed changes or rename crossing the allowlist | Full qualification; both old and new names are checked. Deletes retain their original path. |
| Missing, partial, duplicate, malformed, raced or unavailable change-list data | Full qualification; classification/publication failures cannot make the job green. |
| Weekly Monday 07:23 UTC schedule | Full qualification of the event's exact default-branch SHA, regardless of changed paths. |
| Manual dispatch / release candidate | Full qualification of the required explicit 40-character lowercase `candidate_sha`. A branch or tag name is refused. |

The dependency-free classifier requests every page of the PR files, not the last
commit's diff. It requires the API's independent file count and unchanged head,
base and count before/after acquisition. More than the API's 3,000-file limit is
full qualification. Before skipping, the file records must also match an immutable
base/head comparison, closing a live-head-away-and-back race. Its 300-file or
commit-list truncation limits require full qualification. Unknowns never expand
the allowlist. JSON records event, source SHA, reason, completeness, count and paths.

The native helper requires 103 app ASan / 69 package ASan /
1,919 optimized app / 994 optimized package cases and four expected traps. The app
count includes the five Clear Song Data admission regressions and two additional
writer/export keymap tests, two pan-Q8 runtime/writer cases and one logical pan
release runtime guard and one warm volume-reset runtime guard; the package count
includes the four ordinary absent-keymap, three pan-Q8, two logical pan release
and three warm volume-reset regressions plus the single
`XMColdVolumeEnvelopeTests/testBeforeFirstLxxHoldsFirstValueAndReachesAuthoredPointWithoutRetrigger`
policy regression, plus the six `PureDelayedKeyOffTests` methods for the bounded
bare note97+EDx release policy. Missing/replaced new selectors and stale 988-case summaries
are negative controls alongside existing roster failures. The G31
pan assertion is renamed, without adding a case. Count controls reject stale,
missing, duplicate, extra and non-passing cases, inconsistent summaries and
non-native app execution. The same
source, sanitizer, process/image/options, progress/retirement and trap assertions
remain required. `pipefail` preserves native failures while retaining `native.log`.
Evidence upload uses `always()`, including source and classification receipts.
The #554 physical arm64/cold-host qualification remains independently OPEN;
a relevant failure is never converted to a documentation skip.

PR checkout uses the submitted head, schedule uses `github.sha`, and dispatch
uses `candidate_sha`. An independent workflow step verifies the full SHA against
the real event/input and actual Git HEAD before executing repository Python.
The legacy helper accepts only `pull_request.head.sha`; a clearly marked derived
`helper-event.json` supplies that same verified SHA without changing its assertion.
`source.json` retains the actual event kind, event/workflow SHAs and original event
hash. The compatibility envelope does not represent manual/scheduled runs as PRs.

Concurrency cancels duplicate PR runs only for the **same PR and head**. Distinct
heads are isolated: rerunning an old head cannot cancel the current required check.
Cross-head cancellation is deferred rather than risking that counterexample.
Manual and scheduled runs each have a unique run-ID group and are never canceled
by this policy. They cannot replace a required PR check.

For an exact release candidate, resolve a reviewed candidate commit or tag locally
and dispatch the workflow definition from main after this policy is merged:

```sh
vtx_rc_ref='example-release-candidate'
vtx_rc_sha="$(git rev-parse --verify "${vtx_rc_ref}^{commit}")"
gh workflow run issue516-loop-native.yml --ref main -f "candidate_sha=$vtx_rc_sha"
```

Require the run to succeed, download its `issue516-native-evidence-<run>-<attempt>`
artifact to an explicit `/private/tmp/vtx-.../` destination, and verify
`source.json.source_sha` and the `ISSUE516_NATIVE_PASS` record's `head` in
`native.log` both equal the candidate SHA, with all expected counts and no
failures/skips. Do not use the dispatch run's `headSha` as candidate attestation:
it identifies the workflow ref, which can differ from the tested candidate.
Scheduled main qualification is never a substitute for this exact-candidate gate.

See GitHub's [required-check behavior](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks),
[event/source semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
and [PR file pagination](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests-files).
