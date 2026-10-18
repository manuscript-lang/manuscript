# Independent preimplementation decision: finite pinned lexical reuse

**Decision: approve implementing the finite pinned lexical-cache candidate in
`lexical-proposal.md`, within the constraints below. Reject general strict
selected-graph reuse for this follow-up.** This is permission to build and
measure the bounded candidate, not final acceptance of an unmeasured speedup or
future exact head. Merge acceptance still requires the promised correctness,
race, cold/warm latency and fixed retained-memory evidence.

Reviewed against production `5facbb5ff966904e0b6fe918245d7df7885937ff` /
evidence head `c086eed70aeb9eb6d56689d8aca74a9bf0fb4875`. Read the concrete
proposal, measurement/RESULTS.md, measurement workflow and probe source, and
inspected matrix input metadata/empty working patches. The earlier preliminary
constraints in reuse-design-review.md remain applicable. No production/test
edits, implementation prototype or heavy tests run by this reviewer.

## Why the narrowed proposal survives

The matrix reports actual CompileFile input path plus a hash of complete options
and effective overlay, separating original/proposed rename source. It finds no
repeated exact strict selections for symbols/references on either application
or library controls. Dependency overlap is not a demonstrated exact-cache hit.
Rename repeats N-1 original selections across its collection/validation phase
gap, while its N proposed-overlay checks are distinct. A tiny cache has no
demonstrated useful locality; retaining every collection Program conflicts with
the lifetime bound and skips fresh filesystem validation if used as before
status. A request freezes neither disk nor manifest/alias/symlink resolution.

The library control shows real module-work amplification (121 to 441 indexed
project modules for 11 to 21 strict selected roots), but does not pretend to
have measured an implemented N-graph cache. Count and memory modes are separate;
the latter keeps observers nil and retains no graph fingerprint map. Sampled
2ms memory maxima are correctly labeled lower bounds, and three consecutive
requests in one process are not advertised as independent process samples.
Complete useful result controls and near-baseline post-request/close heap support
preserving the present transient strict checking design.

The independent repeated work is strong enough to justify the smaller candidate:
each new occurrence index lexes the same 47 pinned modules / 303,276 source bytes.
That becomes 1,927 / 4,747 standard lex calls for the 41 / 101 selected-root
application scans, without changing a single semantic selection. Eliminating
repeated immutable lexing does not require a filesystem snapshot, checker
cache, graph union, strictness relaxation or N checked owners. Counts establish
avoidable work, not its eventual latency benefit; the proposal preserves that
distinction and requires the implementation to earn acceptance by measurement.

## Accepted implementation contract

1. One private LSP inventory, created lazily on first lexical lookup, with keys
   derived only from the pinned StandardModules set. Entries contain pinned
   filename/source, a synchronization owner, tokens and lexical error only.
   No request can add a key. The bound is the finite binary-pinned module/token
   set (currently 47 files), rather than a hardcoded count that blocks future
   stdlib additions or an unbounded content-hash dictionary.
2. Exact filename **and** source-value equality is required before a hit. Unknown
   names, changed text and ordinary absolute disk filenames take the original
   lexer.Lex path. Do not use an @std prefix or basename as a sufficient match.
   This helper is lexical pure-function reuse, not native-binding authorization:
   if a caller fabricates exactly the pinned filename and text values, reusing
   their identical lexer output is safe. No extra origin/AST cache is necessary
   merely to distinguish identical values. Existing exact disk-standard
   authorization and immutable virtual documents remain unchanged elsewhere.
3. Cache only token/value data. Do not retain syntax.Module/AST owners, Programs,
   Symbols, Types, Methods, occurrence Info objects or per-query source strings.
   Each Program still obtains its own checked semantics and sourceSymbols;
   reachable standard source implementations remain rechecked normally.
4. Publish inventory and each entry's tokens/error race-safely. Cache misses do
   not write shared maps. The sole production caller must only read the token
   slice: no sort, append into spare capacity or in-place position rewriting.
   Document that internal contract rather than copying the slice on every hit
   and defeating the measured allocation goal. No exported mutable cache API.
5. Keep sourceIndex traversal/order/duplicate-file map overwrite behavior and
   lexical-failure/header-position fallbacks intact. Original byte positions,
   layout-token equal offsets, CRLF and token text are byte-for-byte lexer
   outputs. No separate global header memo is approved or needed in this patch.
6. Keep initialization out of package init, CLI version/help and ordinary
   compiler paths. Call checker.StandardModules only through the lazy demand
   path; keep all compiler/frontend/checker production files unchanged. No GC
   tuning, concurrent checker, cross-generation semantic cache or internal
   compiler/index preemption belongs here.

## Required validation before final acceptance

Compare the candidate helper with fresh lexer.Lex for every pinned module,
including exact token kind/text/Pos/End/layout data and errors. Require repeated
slice identity for a real hit, stable finite key count after many arbitrary and
modified inputs, ordinary disk-path miss, and a malformed modified-source error
control. Removing the source equality gate must fail by an intended assertion.
Race-test concurrent first inventory use and first use of one/all entries.

Keep full existing standard virtual navigation, exact/modified disk-standard,
source standard body/checked identity, sourceIndex, UTF-16/CRLF, rename and LSP
coverage. Compare complete index/feature payloads, not only lengths or the
absence of diagnostics. Count mode must show **unchanged strict CompileFile
selection counts** while post-warm standard lexical calls disappear; the initial
warmup's 47 calls must not be misreported as nonexistent.

For time/memory, warm checker standard state equally on both sides when isolating
lexical reuse. Separately measure fresh-process first-index cost, steady repeated
index/workspace work, finite token count/capacity and post-GC inventory retention.
State which initialization is timed. A retained token inventory is expected and
must be reported as a fixed process-lifetime tradeoff, not mistaken for a leak
or hidden by dropping all references before reading memory. Repeated requests,
edits and arbitrary miss inputs must not grow the key set or retain workspace
sources. Preserve raw samples/iteration counts; do not turn a few means into
p95 or editor-host claims.

Use the already proposed application 41/101 workloads and library 11/21 control;
do not start a broad new compiler investigation. The allocation reduction should
be attributable to immutable lexical work, with complete results unchanged and
no large regression in first use or fixed heap. If warm gains are negligible
relative to retained/cold costs, reject the process cache rather than inventing
another semantic cache to save the result. If retained bytes are unexpectedly
large, the only bounded fallback worth comparing is one per-request immutable
token inventory; do not combine both caches by default.

## Alternatives and stop rule

Doing nothing preserves correctness and is the accepted choice for general
selected-result reuse given zero useful measured symbols/reference hits and
rename's filesystem/owner constraints. The already accepted live rename-index
reuse remains independently valuable. A request-local lexical inventory avoids
fixed process retention but repeats the immutable work next request; it is an
alternative only if the fixed cache cost proves disproportionate. Full
incremental checking, global semantic indices and filesystem snapshots are
rejected for this bounded task.

The finite lexical candidate therefore survives the do-nothing comparison as
the smallest well-supported next implementation. Build it once, run the stated
bounded validation, and either accept its exact head with disclosed costs or
stop. No further architectural expansion is authorized by this verdict.
