# Canonical workspace discovery research — WITHHELD

**Decision: HOLD / do not ship canonical production.** Root and independent review prefer unchanged discovery: the tiny traversal reduction and unchanged read counts do not justify added selected-context rules or the restored alias-analysis amplification. No further dedup implementation was authorized. This is a research artifact retained alongside the separately withheld owner-watcher experiment; neither is a production dependency.

Base: `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`. Final stage1: `082c74274e437bf540ee6834f45c2ca835e5f7d6` (commits `fd6fe456` then `082c7427`). The intermediate fd6 commit is deliberately retained as an I/O regression negative control; neither canonical commit is approved for publication as production. Production scope is exclusively `pkg/tooling/lsp`. Stage2 watcher work is excluded.

The [approved plan](implementation-plan.md) and [independent skeptical design review](design-review.md) explain the separation of physical walk identity from lexical selected analysis context. The parent retains exact-head review and publication authority. The [exact code review](exact-code-review.md) distinguishes static correctness from the final performance HOLD; the [additional identity proposal](additional-identity-plan.md) and [skeptical decision](additional-identity-review.md) explain why the proposed further rules were not implemented.

## Actual operation counts

Eight valid standalone files, one physical root and 1/2/4 directory aliases, both physical-first and alias-first orders, five fixed samples per size/order: **30 samples per head, 60 total**. All samples assert exactly the eight expected names and no duplicate symbols.

| Directory aliases | Base walks / callback visits / file reads | Candidate walks / callback visits / file reads |
| --- | --- | --- |
| 1 | 2 / 10 / 8 | 1 / 9 / 8 |
| 2 | 3 / 11 / 8 | 1 / 9 / 8 |
| 4 | 5 / 13 / 8 | 1 / 9 / 8 |

Counts are identical across all five samples and both orders. See `baseline-work/raw.txt`, `candidate-work/raw.txt`, their `counts.json` and exact source/environment `metadata.json` files. Counters instrument only the LSP discovery calls to `WalkDir`, callback visits and `ReadFile`; compiler/project filesystem work is excluded. Read counts are unchanged in this fixture because baseline directory-symlink walks visited only the symlink entry.

**This establishes less traversal work, not end-to-end latency improvement.** Candidate discovery now produces unopened files in every lexical alias selection context; strict analyses remain separate as required by the reviewed scope. That can increase compiler work compared with baseline's missing alias candidates. Total Go test elapsed was 3.37s base versus 11.48s candidate for the entire count probe; these are not controlled latency samples and are not presented as a speedup. A future reviewed selected-context deduplication may address duplicate strict analyses without erasing standalone/manifest selection differences. No extension-host latency, p50/p95, compiler-cache or peak-memory claim follows from these probes.

## I/O behavior and negative controls

`read_error_probe_test.go.txt` injects `os.ErrPermission` only at the LSP discovery read boundary for an authoritative open file. The unchanged compiler still checks actual source and overlay confinement. Both base and final candidate preserve main/value/sibling workspace symbols, exactly three declaration/import/use references and zero reads of the open-backed file. Removing the open snapshot must surface the injected closed-file read error. Exact intermediate fd6 fails by losing the sibling symbol, reproducing the independently found regression; the correction passes.

Three deliberate final-candidate mutations all fail substantive tests (exit1): canonicalizing only the visited key loses unopened alias-first sources; dropping unique physical-overlay text emits stale disk source; dropping ambiguous physical suppression invents a third disk document for two conflicting real aliases. Each directory includes raw failure and exact source hashes. Production tests also exercise encoded divergent URI symbols/requested text, real symlink conflicts, private snapshots across shared walks, selected standalone and symlinked-manifest contexts, cancellation and recursive-scope distinction.

The full exact-stage1 LSP package suite passed (`lsp-tests.txt`, 5.004s). It was run with a read-only Go source overlay restoring server/snapshot to fd6 and hiding the separately uncommitted stage2 watch file; the tested discovery/workspace/test sources exactly equal final082. No permanent production test seam was introduced. Independent exact-head checks remain the parent's gate.

## Reproduce

Requires a Linux/macOS checkout containing these commits, symlink support, pinned Go1.25.1 (`.go-version`) and a writable Go cache. Standard source tree ID and `.msversion` pin are retained per run in `metadata.json`; the runner hashes every original LSP Go source before instrumentation. It rejects tracked non-LSP differences and untracked non-LSP Go/Manuscript sources so the actual compiler/standard source matches the selected commit; current base/candidate differ only within LSP. All subprocesses set `GOMAXPROCS=2`. No downloaded binaries or generated checkout are included.

```sh
ROOT=/path/to/manuscript
GO=/path/to/go1.25.1/bin/go
CACHE=/tmp/discovery-go-cache
python3 run_probe.py --checkout "$ROOT" --commit b49c0c99 --go "$GO" --cache "$CACHE" --case work --output /tmp/discovery-base
python3 run_probe.py --checkout "$ROOT" --commit 082c7427 --go "$GO" --cache "$CACHE" --case work --output /tmp/discovery-candidate
python3 run_probe.py --checkout "$ROOT" --commit 082c7427 --go "$GO" --cache "$CACHE" --case read-error --output /tmp/discovery-read-error
python3 run_probe.py --checkout "$ROOT" --commit b49c0c99 --go "$GO" --cache "$CACHE" --case read-error --output /tmp/discovery-base-read-error
# Expected failure, exit1:
python3 run_probe.py --checkout "$ROOT" --commit fd6fe456 --go "$GO" --cache "$CACHE" --case read-error --output /tmp/discovery-fd6-control
python3 run_probe.py --checkout "$ROOT" --commit 082c7427 --go "$GO" --cache "$CACHE" --case work --mutation canonical-key-only --test TestDiscoverySharesPhysicalWalkButRetainsWrittenPaths --output /tmp/discovery-canonical-control
python3 run_probe.py --checkout "$ROOT" --commit 082c7427 --go "$GO" --cache "$CACHE" --case work --mutation drop-overlay-text --test TestDiscoveryUsesUnsavedAliasTextForDiskCandidates --output /tmp/discovery-overlay-control
python3 run_probe.py --checkout "$ROOT" --commit 082c7427 --go "$GO" --cache "$CACHE" --case work --mutation drop-ambiguous-suppression --test TestDiscoveryDoesNotInventDiskVariantForConflictingAliases --output /tmp/discovery-ambiguity-control
```

`run_probe.py` restores immutable Go sources using a temporary `go -overlay`, adds exactly one external probe file, records raw output/exit/source hashes and removes generated sources afterwards. It never checks out, edits or publishes repository files. The `.go.txt` suffix keeps report copies out of normal Go package discovery.

## Reconstruct unpublished research sources

The original candidate commits are intentionally unpublished. These text patches are the immutable production-and-test sources; no original Git object is required to reproduce their content. In a disposable worktree based on public b49, apply `research-candidate.patch.txt`, create a local commit and pass that local commit to the same loader. The resulting commit SHA differs, but source hashes and standard-source pins must match the retained metadata. For the intermediate I/O regression, use `intermediate-regression.patch.txt` in a second disposable b49 worktree.

```sh
git -C "$ROOT" worktree add --detach /tmp/discovery-research b49c0c99
git -C /tmp/discovery-research apply /absolute/path/to/research-candidate.patch.txt
git -C /tmp/discovery-research add pkg/tooling/lsp/discovery.go pkg/tooling/lsp/discovery_test.go pkg/tooling/lsp/workspace.go
git -C /tmp/discovery-research -c user.name=Reproduction -c user.email=reproduction@example.invalid commit -m 'Local discovery research source reconstruction'
python3 run_probe.py --checkout /tmp/discovery-research --commit HEAD --go "$GO" --cache "$CACHE" --case work --output /tmp/reconstructed-discovery
```

Reconstruction is only a local experiment, not a suggestion to merge the withheld change. The separate owner-watcher experiment excluded discovery.go/workspace.go changes and was also withheld.
