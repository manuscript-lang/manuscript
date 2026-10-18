# Finite pinned standard lexical reuse proposal

Baseline production: 5facbb5ff966904e0b6fe918245d7df7885937ff (evidence head c086eed).
Scope: pkg/tooling/lsp only. No checker/frontend/compiler production changes.

## Evidence and decision

The external matrix measured zero repeated exact strict selections for workspace
symbols/references (41/101 application roots, 11/21 library roots). Rename repeats
N-1 before selections across phases, but retaining their graphs scales with
selected closures, and cached success would remove fresh disk validation.
Therefore reject general request-local checked-result reuse in this follow-up.
Preserve every strict before/after CompileFile call.

Each new sourceIndex currently lexes 47 pinned standard modules, 303,276 bytes.
Application symbols/references repeat this 1,927/4,747 times per request. A finite
lexical cache can remove this repeated immutable input work without reusing any
checked identity. Counts alone do not establish a latency gain: acceptance is
conditional on cold/warm latency and fixed retained-memory measurements.

## Concrete implementation

Add one private LSP lexical inventory initialized lazily on the first sourceIndex
token lookup. Its fixed key set comes only from checker.StandardModules(), mapping
exact canonical pinned filename to an entry holding pinned source string,
sync.Once, []lexer.Token and error. Each entry lexes once on first exact use.
Retain no syntax module, AST, Program, Symbol, Type, occurrence or workspace text.
Cache lifetime is the LSP process; arbitrary inputs cannot add keys. The current
47-file pinned inventory bounds it independently of workspace size and edits.

Lookup requires exact filename AND source equality. A forged/modified @std file,
ordinary disk filename (even exact pinned text), and unknown filename fall back
to lexer.Lex. Failure/error behavior is unchanged. A module list with duplicate
filenames still fills the sourceIndex token map in its existing order; only the
lexical call changes. The returned token slice is private and read-only at its
sole production caller, which already only searches/reads it. Keep per-Program
sourceSymbols and checked standard implementations unchanged. No header cache,
global semantic index or cross-generation checked cache is introduced.

## Validation and rejection threshold

Tests compare exact cached/uncached tokens (including positions/layout), repeated
slice identity, finite keys after arbitrary/modified inputs, error fallback and
concurrent first use under race. Existing standard navigation/body-identity,
UTF-16, sourceIndex/rename and full LSP tests remain required. Deliberate mutant
removing source equality must fail the modified-pinned-source test.

Benchmarks use the same sourceIndex fixtures and external request matrix on a
clean baseline and candidate, with checker.StandardModules warmed equally for
warm tests. Fresh-process first-index measurements report latency, allocations,
token count and post-GC retained inventory bytes separately. Compare full result
payloads, not lengths only. Measure application 41/101 workspace operations and
library 11/21 control; count mode must preserve strict selection counts while
standard lexical calls disappear after first use. No concurrent heavy probes.

Do nothing is preferred if the gain is negligible relative to retained cost or
correctness needs expand into checked-identity caching. A bounded per-request
token cache avoids process retention but repeats identical work every request;
measure it as an alternative if fixed retained bytes are unexpectedly large.
No startup claim until fresh-process evidence exists; no editor-host claim.
