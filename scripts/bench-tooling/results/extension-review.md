# Extension independent exact-head review

**Disposition: ACCEPT — no blocking finding in integrated exact head `85c25ffd3821fc2ba76a887423c5a5ea0e0c0ec2`.**

Current base: `b4b22bf9c51bca571251687d3aa148901761a8aa` (main, #653).
Original base: `a988705cbd5ed9c7424ac891aa42893c2805474a`.
Reviewed checkout: `/workspace/manuscript-tooling-extension`, clean at the exact head above. The extension diff remains the same two files (248 additions, 15 deletions). This is an independent static review; CI/publication remains the parent's responsibility.

## Main integration refresh

The accepted original extension head was `0e8556eccd6447ca8bbfd4fc559db2aef6831823`. The new head is a merge with parents that original head and `b4b22bf9c51bca571251687d3aa148901761a8aa`.

Read the complete original-head-to-integrated-head delta: it contains only `pkg/tooling/lsp/semantic.go` and the 103-line `pkg/tooling/lsp/performance_test.go` from #653. Both files are byte-identical to the separately reviewed/accepted stage-one head `1072850b4e2a551e6929bb3c80584db0e529121a`; see `stage1-review.md`. The extension source and extension test file are unchanged from their accepted original head. Diff against the new main base contains only the same two extension files. No additional integration behavior or conflict resolution was introduced, and `git diff --check b4b22bf9 85c25ffd` passed. This evidence supports acceptance of the resulting exact head, not just its earlier branch state.

## Review performed

Read the complete diff, current AGENTS/manuscript-change/tooling guidance and relevant tooling lessons. Traced extension activation, all client ownership assignments, content/task providers, command/config restart paths and deactivation. Read the supplied implementation log, positive test output, negative-control output, count runner and before/after JSON.

Inspected the installed dependencies used by the implementation evidence:

- `/workspace/tooling-perf-review/vscode/node_modules/vscode-languageclient`: version 10.1.2.
- Its `lib/common/client.js` sendRequest, start, shutdown/stop, cleanup and watcher registration.
- Its `lib/node/main.js` process cleanup after shutdown.
- Its `lib/common/fileSystemWatcher.js` raw watcher listener ownership.
- `vscode-jsonrpc` 9.0.3 request argument/cancellation handling.

The reviewed lockfile is byte-for-byte identical to the evidence installation's lockfile. Both reviewed source/test files are byte-for-byte identical to the implementation worktree files named in the supplied test/count evidence. The implementation log's older worktree/branch names and “No commit” wording describe its preparation phase, not the current reviewed commit.

Light checks performed:

```sh
git rev-parse HEAD
git status --short
git diff --stat a988705c 0e8556eccd6447ca8bbfd4fc559db2aef6831823
git diff a988705c 0e8556eccd6447ca8bbfd4fc559db2aef6831823
git diff --check a988705c 0e8556eccd6447ca8bbfd4fc559db2aef6831823
cmp extensions/vscode/package-lock.json /workspace/tooling-perf-review/vscode/package-lock.json
cmp extensions/vscode/extension.js /workspace/manuscript-tooling-fixes/extensions/vscode/extension.js
cmp extensions/vscode/tests/extension.test.js /workspace/manuscript-tooling-fixes/extensions/vscode/tests/extension.test.js
```

All checks above succeeded. No tests, builds, dependency installs or timing work were started by this reviewer during the parent's measurements. No source edits, push or external review comments were performed.

## Lifecycle and ownership assessment

No blocker found in the reviewed implementation.

| Path | Static assessment |
| --- | --- |
| Initial startup | `extension.js:142-143` records the promise and cleans up a failed client before preserving the activation rejection. Restart joins the handled startup result instead of trying to stop a still-starting client. |
| Overlapping restart commands | `extension.js:81-94` installs one shared promise before its first asynchronous continuation, so overlapping callers share the same replacement sequence. |
| Configuration changes during stop | Replacement reads the latest configured path after the stop completes. Intermediate configuration notifications coalesce. |
| Configuration changes during replacement start | The loop rechecks the configured path after awaited start/failed-start cleanup and performs a further replacement when needed. |
| Failed replacement | The replacement is owned by `client` before starting; catch cleans it through `stopCurrent`, logs the failure and retains future restart admission. A later explicit restart can create another client. |
| Deactivation during initial or replacement start | `shuttingDown` is set synchronously, preventing new restarts. Shutdown joins initial/replacement work and then stops the remaining owner. A replacement suppressed after stopping cannot be started by that pending restart. |
| Repeated deactivate | The memoized shutdown promise prevents overlapping duplicate cleanup. |
| Content during lifecycle work | Provider waits the currently pending restart or initial startup, then rechecks cancellation, shutdown and ownership before selecting the client. A recovered replacement is not blocked permanently by the old initial-start rejection. |
| Shared output/watcher | Extension subscriptions retain these resources. The client clears its raw watcher event subscriptions on stop, without disposing the caller-created watcher. Replacements can reuse the same watcher and log channel. |

The code serializes lifecycle work rather than adding a cross-client cache or independent background worker. The existing client library supplies stop timeouts and process cleanup. The extension does not establish prompt shutdown if an initial/startup promise never settles; the review does not claim a bounded initialization policy.

## Provider contracts and watch semantics

The content provider passes the supplied VS Code cancellation token after the request payload. Pinned client10 explicitly accepts this argument shape (`lib/common/client.js:581-631`), recognizes pre-cancellation, and passes parameters/token onward. JSON-RPC recognizes real tokens through their cancellation flag and event (`vscode-jsonrpc/lib/common/cancellation.js:57-63`) and subscribes the event when sending. No payload/schema change is introduced.

VS Code documents cancellation arguments for both providers and the fourth `findFiles` argument. Its glob syntax supports brace alternatives and `**` matching zero or more path segments. Thus the new pattern covers root/nested `.ms` sources and exact `ms.toml` manifests, while excluding unrelated TOML. This is narrower event selection; it does not prove fewer native watcher handles. [Official VS Code API](https://code.visualstudio.com/api/references/vscode-api)

Task discovery retains its existing include/exclude scope and all uncanceled operations. Pre-canceled calls avoid searching. Cancellation after awaited discovery prevents creating task objects from stale results. The per-task check also prevents returning a partially created list if cancellation is observed during enumeration. The loop remains synchronous; this patch adds no event-loop yielding or task limit.

## Test/evidence assessment and limits

The supplied `extension-tests.log` reports 36 tests: 30 passed, 6 native/debugger cases skipped, zero failed/canceled. This is inspected evidence from matching files, not an independently rerun suite. It covers startup/restart failures, overlapping restarts, configuration changes while stopping/starting, deactivation races, watcher samples and provider cancellation checks.

The selected new tests against the external base snapshot report 5 assertion failures and zero canceled tests. These are useful negative controls: the base fails watcher selection, token forwarding, canceled task enumeration, restart ownership and failed-replacement cleanup.

The supplied count runner uses the actual selected extension source with explicit editor/client mocks. Its reported differences are consistent with the changed code:

- Twenty overlapping restart requests: replacements/old-client stop calls fall from 20/20 to 1/1.
- Running mock clients after deactivate fall from 19 to 0.
- Pre-canceled discovery over 1,000 available manifests changes from one search/4,000 task objects to zero/zero.
- Uncanceled discovery retains 4,000 tasks.
- Pre-canceled content requests fall from one to zero.

These are operation and mock ownership counts, not actual server process counts, RSS, extension-host latency, or proof of operating-system watcher behavior.

Nonblocking qualification: fixture tokens contain only `isCancellationRequested`; they do not implement `onCancellationRequested`, so tests establish forwarding and guard placement rather than actual JSON-RPC cancellation events. Real VS Code tokens satisfy the pinned library's structural contract, which was independently read. The enumeration test flips its token synchronously from the mock Task constructor; it does not demonstrate asynchronous user cancellation interrupting a non-yielding production loop.

Likewise, `path.matchesGlob` tests representative pattern semantics in Node, not a running VS Code watcher. Official glob contracts support the pattern, but platform-sensitive event delivery remains outside the evidence. No further test expansion is required to accept this scoped change.

## Final disposition

ACCEPT this exact head with no blocking issues. Its claims should remain about redundant operations and serialized lifecycle ownership. The supplied Node runtime differs from the repository pin (24.19.0 versus 24.13.0), real extension-host validation is unavailable, and six native tests were skipped; none of those limits is hidden by this verdict.

Exact-head CI must pass before the parent changes PR readiness or merges. Any rebased or combined successor head requires its own resulting-diff review; this verdict does not automatically approve later changes.

