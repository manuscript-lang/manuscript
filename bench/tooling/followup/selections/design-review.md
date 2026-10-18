# Preliminary skeptical review: bounded editor reuse follow-up

Base inspected: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8` in
`/workspace/manuscript-tooling-followup`. Production checkout was clean at the
start of this review. Read current AGENTS.md, manuscript-change/tooling/compiler/
simplify guidance, relevant expert constraints, and current snapshot, workspace,
rename, sourceIndex, pinned-standard and frontend root-selection paths.
No implementation edits, tests or benchmarks performed by this reviewer.

**Status: no broader reuse design approved yet.** Concrete proposal and the
independent exact-selection/peak-memory probes are pending. This preliminary
review does not block the parent's separate small cancellation/checkpoint and
existing-index reuse changes; those need their own exact-head review. Keep the
follow-up bounded: choose the smallest option justified by the incoming evidence,
including doing nothing beyond that first patch.

## What the present code actually repeats

workspace/symbol and workspace references iterate discovered selected roots once
per request after their current URI deduplication/discovery rules. Each calls
workspaceAnalysis with AnalyzeOnly=true, Recover=false and Module=current file.
Ordinary request-local **exact-selection** graph memoization therefore has no
obvious high hit rate on these loops. It is not enough to show that their
dependency closures overlap; closure overlap is not exact selection equivalence.

Rename is different: discovery checks most target roots strictly, then later
validation repeats strict before checks for those roots. The primary document's
incoming result is recovering, so it cannot replace its strict before check.
The after checks use the modified overlay and cannot reuse any before result.
Local-binding rename has a single primary target and usually no duplicate strict
selection at all. For cross-file rename, the repeated roots occur in different
phases, separated by all discovery roots and proposed edit construction.

Retaining all discovery Programs until validation would reintroduce the rejected
N-selected-closure memory growth. A one/two-entry LRU may avoid that memory cost
but get essentially zero useful hits across the phase gap. A small map of
success/error summaries would use little memory but has a separate filesystem
correctness issue described below. Measurements must identify actual repeated
equivalent calls and the avoided work, rather than infer a benefit from the
word “request-local.”

sourceIndex independently re-lexes every pinned standard module for every
uncached selected-root Program. That lexical text is immutable and shared even
when checker identities differ. This is a plausible low-risk reusable boundary,
but it trades repeated allocations for a process-lifetime retained token set.
Measure that fixed retained/cold cost alongside steady savings before approval.

## Non-negotiable selection and identity constraints

- A compiler Module selection replaces the configured entry
  (`frontend/modules.go`), rather than adding a root. Default recovering graphs,
  selected recovering fallback graphs and strict selected-root graphs remain
  distinct. Neither membership nor superset graph coverage proves equivalent
  diagnostics. In strict libraries an initial selected-entry parse/import failure
  can discard all modules, while a later discovered-module failure can retain
  neighbors. Do not infer equivalence from the final successful module set.
- Preserve AnalyzeOnly/Recover/Module/Tests/ProjectSources/Entry and private
  ScopeMarker differences. A restricted workspace helper may fix most options by
  construction; do not build a misleading generic cache whose key ignores
  options supplied by new callers. Successful and failed selections both retain
  the original diagnostic and source-root behavior.
- Resolve nearest manifests with the existing requested path spelling first;
  malformed nested manifests do not inherit parent aliases. Keep standalone
  file roots separate, and canonicalize manifest containing directories rather
  than manifest-file destinations. New unsaved overlays and dangling symlinks
  remain governed by project.SourcePath/CanonicalOverlay.
- Distinct URIs decoding to one filename can supply different requested text.
  analyzeWith's requested-document override means even one unchanged docs map
  does not always produce a common overlay. Preserve the existing ambiguous-URI
  sharing opt-out, or include the actual request-specific input in any local
  reuse decision. Never choose one conflicting overlay silently.
- Rename's original and modified overlays are different ownership domains. An
  after result, index or validation status cannot reuse a before entry. Preserve
  every currently checked root, label/field/type/interface identity, collision
  check, returned URI/version and original byte offset.
- Checked Programs, Symbols, Types, Methods and occurrence Info objects must not
  become a global immutable-stdlib cache. Reachable source standard
  implementations are rechecked within each owning Program, and lexical
  implementation/contract evidence can differ. Only lexical text/tokens/header
  positions detached from checked identities are candidates for global reuse.

## Filesystem consistency is not guaranteed by request lifetime

The serial LSP loop fixes its docs map during a request, but does not freeze the
filesystem. CompileFile rereads manifests, source dependencies, alias targets,
directory discovery and symlinks on each selected check. A file watcher event
can be queued while a long request runs, and an external process can modify disk
without waiting for the server. Consequently “same selected root + same overlay
owner + same request” alone does not prove that the previous strict result is
the result a fresh current call would return.

This matters especially to reusing rename discovery status as its later before
validation. A source dependency can change on disk after discovery; a modified
overlay can subsequently mask part of that old source when validating the
proposed edit. The current fresh before check can reject the changed workspace,
while a cached success could allow an edit based on stale content. Existing
baseline TOCTOU does not make removing that check behavior-preserving.

Do not quietly redefine all requests as frozen filesystem snapshots. Such a
claim would need complete manifest/configuration, transitive source, discovery
and path-resolution capture, not only open source text, and is outside this
bounded follow-up. Metadata-only stamps are not automatically sound: same-size
edits, timestamp granularity, create/delete and symlink target changes need
consideration. Hashing/revalidating every dependency may cost more than the
work supposedly saved. Prefer no strict-check reuse unless the concrete
proposal identifies a narrower repeated operation with demonstrably stable
inputs. This review will not approve stale before-validation as a performance
shortcut.

## Bounded standard lexical reuse candidate

The smallest plausible design caches lexer.Token slices for the finite pinned
module set only. Initialize lazily on first index demand, not package import or
CLI startup; publish immutable data with sync.Once or an equivalently race-safe
one-time owner. Retain no workspace documents, source versions, checked graphs
or caller-generated cache keys. The bound should be stated in pinned module/
token counts and measured bytes, independent of project roots, edits or query
count. Do not use an unbounded cache indexed by arbitrary module source hashes.

Use cached tokens only for the pinned module identity and exact pinned source.
A filename prefix such as @std/ by itself does not authorize a disk or modified
module to use pinned positions. Existing exact disk-standard authorization and
read-only virtual URI behavior remain separate. Duplicate Program/pinned module
entries in sourceModules must retain current token-selection and occurrence
dedup behavior; a cache must not substitute global checked occurrence objects.

Tokens contain original source positions and text, not checker pointers. Their
internal slice must remain read-only after publication; sourceIndex currently
only reads it. Retain lexer failure/header fallback semantics rather than adding
panic paths. Keep current binary-search offset assumptions (nondecreasing
original offsets, equal layout-token positions) and UTF-16/CRLF conversion
unchanged. A separate global header memo is unnecessary unless measurements
show a further benefit: token reuse already removes the repeated lexing and
preserves the simple bounded header lookup.

Pinned lexical-cache growth is fixed, but its cold allocation/retained heap is
not free. Do not hide that cost behind a warm benchmark or compare a warmed new
cache to a cold old standard loader. Measure fresh-process first use and steady
repeated sourceIndex/workspace requests separately. Race-test concurrent first
use and verify no writable checked-standard data is reused globally.

## Alternatives, including doing nothing

1. **Do nothing beyond the small cancellation/index patch.** Lowest semantic and
   ownership risk; preserves known uncanceled workspace latency. This is the
   right choice for exact-selection caching if the probe shows unique roots/no
   useful bounded hits or if filesystem validity costs erase savings.
2. **Reuse an already supplied occurrence index within one unchanged checked
   result/request.** Removes immediate duplicate index construction with no
   compiler-selection or filesystem-cache claim. Keep ownership tied to the
   supplied Program. Parent's first local patch can stand alone.
3. **Finite pinned lexical cache only.** Plausibly removes significant repeated
   fixed index allocation across transient workspace graphs while preserving
   every compiler invocation. Prefer this over a new graph-cache abstraction
   if isolated measurements justify its fixed memory and first-use cost.
4. **Small exact-selection local memo.** Consider only if actual request traces
   demonstrate hits and stable inputs, with explicit entry/byte bounds and
   eviction. A request-bound dictionary of N complete Programs is rejected;
   even a fixed number of very large graphs needs peak-memory evidence.
5. **Broader snapshots/incremental checking/concurrent workers.** Rejected for
   this follow-up. These would change scope and require evidence/design beyond
   the current bounded investigation.

## Evidence required for a bounded approval decision

The incoming proposal should name one concrete retained value, its owner/key,
maximum lifetime/entry or byte bound, hit scenario, invalidation/eviction rule,
and the code path removed. Avoid a generic infrastructure layer for hypothetical
reuse. Before/after speed and peak/retained bytes must use the same valid source
and complete results, without concurrent heavy load.

For exact selections, record request operation/root/options/overlay phase and
actual duplicate count at small/medium/large N. Include local and cross-file
rename, source/test libraries, malformed selected roots and bad imported roots.
Demonstrate whether a bounded cache can hit across the real call order. If reuse
would skip fresh disk validation, include a deterministic between-phase disk/
manifest/symlink mutation control; a stale result is a correctness failure.

For standard lexing, isolate sourceIndex allocation/time with immutable stdlib
loading warmed on both sides, then measure cold first use, repeat workspace
latency, pinned token count/retained bytes and post-request heap. Full index/
feature payloads must match, including checked standard methods, source-body
identities, navigation inside virtual stdlib and exact disk/modified-source
boundaries. Concurrent first-use race evidence is required for a new global
cache. Repeated requests/edits must not increase the number of cache keys.

Cancellation controls must establish that later phases do not start after
observed cancellation, while uncanceled controls retain every result and rename
check. No partial successful result, arbitrary truncation, deadline skip,
compiler-internal preemption claim or N-retained selected graph family is an
acceptable way to improve the benchmark.

**Next decision:** await the concrete proposal and existing delegated probes.
Do not expand exploration indefinitely: reject exact-selection reuse if useful
safe bounded hits are absent, and approve only the independently beneficial
smallest option supported by the measurements.
