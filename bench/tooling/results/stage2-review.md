# Independent exact-head review: stage 2

**Accept `42fa428e9eef86608f6b65d15f8668a0e9d47619`**, diff from
`1072850b`, for the position/documentation/index change. No correctness blocker
found in this static review. This acceptance does not replace the parent's
package/race checks or measured benchmark evidence.

Reviewed the clean detached checkout `/workspace/manuscript-tooling-stage2` at
the full SHA above. Read its AGENTS.md and used the previously loaded
manuscript-change/tooling/compiler/simplify/taste workflows and applicable
experts. Inspected the entire diff, current consumers, lexer original-offset
mapping/emission, parser recovery/rebasing, standard-document identities and
existing semantic payload regression. No production/test edits, no tests or
heavy commands while parent stage 2 benchmarks were active.

## Integration-head acceptance refresh

Also **accept exact head `96cfc2b39ce9b4564a6910390090a75761d49358`**.
Read-only verification found `git diff --exit-code 42fa428e9eef86608f6b65d15f8668a0e9d47619 96cfc2b39ce9b4564a6910390090a75761d49358`
empty with exit 0. Both commit tree objects are
`e52626466c93aca07c55d33d32167d2308312599`. Therefore the prior accepted code and
tests are byte-identical; only integration ancestry changed. CI results for the
new commit remain owned by the parent; no new test-pass claim is made here.

## Correctness checks

- **Token binary search:** `index.go` and `symbols.go` search the first token
  whose original Offset is >= the declaration offset, then retain the old
  forward header loop exactly. Lexer's scanner only advances; CRLF
  normalizeSource originalOffsets maps to strictly increasing source byte
  positions. Layout tokens may share offsets, but `>=` returns the first such
  token, preserving old behavior. String/interpolation scanning consumes source
  before emitting its one enclosing token; it does not introduce retrograde
  nested tokens. A lexer panic returns nil tokens, so malformed source retains
  the previous empty-token/header-position fallback. Recovery rebases retained
  declarations without altering original byte/line offsets.
- **Symbol maps/modules reused once:** sourceIndex reads symbol maps and the
  module slice; it does not mutate them. Moving sourceModules outside its loops
  and retaining one StandardExports copy per module changes allocation and
  repeated lookup work, not checked identity. Imported standard names still
  use the imported module's StandardExports rather than the containing module
  map. Program-specific standard bodies/operations remain program-specific.
- **Indexed positions:** newSourcePositions starts with byte 0, includes byte
  after every LF, and therefore handles empty text and trailing newline with a
  valid last line. Upper-bound search selects the correct line at newline,
  EOF, and clamped offsets. No token ordering assumption is required for these
  queries. CR remains a column character exactly as in the old Position;
  splitting a UTF-8 sequence or encountering malformed bytes produces the same
  RuneError widths as the old []rune conversion.
- **UTF-16 width:** Go string range and []rune share decoding behavior;
  utf16RuneWidth returns two units only for >U+FFFF, otherwise one. This matches
  utf16.Encode for every decoded scalar/RuneError. Offset's only change factors
  out that same width calculation; negative/out-of-range behavior,
  surrogate-split rejection, CR/LF handling and edit clamping remain in the
  existing code.
- **Documentation:** declarationDocumentation now locates the LF before the
  declaration's original offset, scans immediately preceding physical lines,
  and reverses notes once. It preserves TrimSpace, one leading # removal,
  contiguous-block boundaries, blank # lines, blank-line detachment, order,
  indentation, CRLF and source ownership. Declared positions remain anchored
  to the header line for constants/ordinary declarations/methods; recovery
  retains original offsets. Nil/invalid-position guards are safe. Standard
  doc lookup still uses immutable checked sourceModules. There is no separate
  standard prose catalog or signature reparsing.
- **Document fields:** replacing strings.Split(tail,"\n")[0] with
  IndexByte to the first LF produces the same line slice and trailing CR trim.
  The existing assumption that field offsets belong to document source is
  unchanged, including recovery. Selection/full ranges now use the batch
  position index without changing the source text used for conversion.

## Tests inspected for meaningful results

The added position oracle retains the full previous allocation-based algorithm
and compares all byte offsets (including inside UTF-8 sequences), negative/EOF
clamping, empty text, CRLF, astral characters and malformed bytes. Offset tests
compare both errors and values against the old strict/clamping implementation,
with an explicit surrogate-split negative control.

Consumer tests require exact semantic token arrays rather than nonempty output,
including unfinished-string fallback. Document-symbol tests require four
retained declarations, compare header selection to the previous full-token
scan, and assert Unicode field range endpoints in valid and recovered LF/CRLF
source. Documentation tests require every named recovered declaration, exact
expected prose/detachment, and positive documentation coverage across all checked
standard declarations/methods. Existing TestSemanticProjectModuleIdentity
requires checked imported-call/parameter classification that deliberately fails
in lexical negative controls, plus symlink equivalence. These guard against a
speedup obtained by losing analysis or suppressing output.

No new sourceIndex-specific whole-index oracle was added in this diff; existing
semantic/navigation/reference tests cover its consumers, and the binary-search
transformation is structurally equivalent given the established lexer ordering.
A future recovery/lexer offset change should explicitly preserve that ordering.

## Allocation/scaling assessment and limits

The change removes the per-declaration standard-export map copies, token-prefix
header scans, whole-module line arrays per documentation candidate, UTF-16
temporary buffers, and repeated source-prefix newline counting in batch
semantic/document-symbol consumers. Line starts cost O(number of lines), with
no per-byte mapping table. Documentation extraction allocates proportional to
the actual comment block, plus existing sourceModules slice overhead; it no
longer allocates all source lines for undocumented declarations.

**Remaining nonblocking limit:** sourcePositions.position still scans the UTF-8
prefix of its selected line. Many tokens on one very long physical line can
therefore cause quadratic within-line decoding, even though many-line prefix
counting is fixed. Standalone Position still counts source-prefix newlines for
callers outside the changed batch consumers. Do not claim every possible LSP
position workload is now linear. A monotonic cursor encoder for ordered token
streams could address the long-line case separately if a measured workload
justifies it; it is not needed for correctness or acceptance of this patch.

Parent owns timing evidence and tests. This review makes no new speedup or
test-pass claim and does not approve any later snapshot/scheduling changes.
