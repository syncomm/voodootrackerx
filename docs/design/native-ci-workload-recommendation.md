# Native CI workload recommendation

**PROPOSED — follow-up CI contract, not workflow policy.** PR #556 preserves the
existing workflow triggers and qualification gates. Its necessary evidence
integration correction does not change scheduling or relax proof requirements.

The issue516 workflow introduced by #552 runs its expensive native ASan and
optimized qualification on every PR. Recommend retaining ordinary build, unit,
parser, fixture and hygiene checks on every PR while classifying when the full
native workload is required:

| Change or event | Recommended native workload |
| --- | --- |
| Playback, preparation, transport, audio host/mixer, module model/parser, sample ownership or their integration/tests/fixtures | Full submitted-head qualification. Start with conservative `app/`, `core/`, `tests/`, package/build and relevant diagnostic-tool dependencies; narrow only with classifier tests. |
| Native workflow, helper, process-attribution or sanitizer/trap controls | Full submitted-head qualification, including classifier changes. |
| Clearly unrelated prose, artwork or tooling | Explicit recorded classifier decision; retain the ordinary PR checks. Unknown dependencies require full native qualification. |
| Weekly schedule and manual dispatch | Full native qualification to detect runner, Xcode and host-environment drift. |
| Release candidate or release gate | Full native qualification of the exact candidate commit, independent of the PR classifier. |

Keep a stable required-check name on every PR. A lightweight classifier and final
gate can record an explicit not-required result; excluding the entire workflow
with path filters can leave required branch-protection checks pending. Relevant
changes must still require the full job's success. The final gate must run even
after a dependency fails and explicitly validate its required results; see
[GitHub's required-check guidance](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
Preserve exact source-head,
selector/count, process/image/options, sanitizer initialization, native delivery,
retirement and optimized trap assertions. A scheduled run on another commit
cannot replace a required submitted-head run.

Deduplicate superseded PR heads with an explicit concurrency group. Run focused
checks before submitting a stable candidate; avoid repeatedly restarting the full
qualification for the same unclassified failure. Capture stage durations and
classifier decisions so workload reduction is measurable. #554's host-retirement
investigation remains separate; scheduling must not turn a failure into a skip.

Implement this recommendation in a separately reviewed CI change with branch
protection verification and positive/negative dependency-classifier tests. This
note authorizes no workflow disablement or release-gate waiver.
