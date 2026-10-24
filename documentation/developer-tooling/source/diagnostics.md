+++
title = "Diagnostics"
weight = 2
+++

# Diagnostics

Each diagnostic has a stable rule code, a message, and a source position, plus an exclusive end when the extent is known. Coordinates follow the [metadata span contract](../debugging/metadata.md).

## Message shape

Messages read `<cause>; <fix>`. The cause has stable wording naming the offending name, type, or count.

The fix says what to write, such as `did you mean 'count'?`, `add: import panic from "@std/core.ms"`, `declare it with 'var x = ...' instead of 'let'`, or the valid arguments, members, cases, or exports. Codes classify only the text before the first `; `, and follow-on errors that restate an earlier one are not reported. New messages extend the matching tests in `crates/ms-check/tests`, `crates/ms-syntax/tests`, or `crates/ms-cli/tests`.

## Explaining a violated rule

A diagnostic names the violated rule and the declaration or call site involved. Runtime closed-resource errors carry operation and source locations separately.

`ms check file.ms --json` emits `{"format": 1, "diagnostics": [...]}`. Each diagnostic has `code`, `phase`, `message`, and `position` with `file`, one-based `line`/UTF-8 byte `column`, and original-byte `offset`. Empty results use `[]`. CRLF normalization preserves original offsets.

Several inputs share one document; see [analysis selection](../implementation.md#selecting-independent-analysis-inputs).

- Optional `end` has the same coordinate fields (exclusive). Parser token errors and failed import names provide it.
- Optional `fix` has `position`, exclusive `end`, and `replacement`: replace that byte range in the original snapshot, then recheck. Redundant prelude imports, misspelled names, labels and types with one `did you mean` candidate, and unresolved standard names (an `import` inserted at the top of the file) carry one; string-match rewrites and ambiguous imports get prose only. `ms check --fix` and `ms lint --fix` apply these edits in place (skipping overlaps), then report what remains.
- Consumers must tolerate absent optional fields.

| Code | Family |
| --- | --- |
| MS1000, MS1001, MS1002 | Grammar, literals/text, layout |
| MS2001, MS2002, MS2003 | Names/members, modules, redundant canonical prelude imports |
| MS3000, MS3001 | General typing, exact types/operators |
| MS3002-3004 | Duplicate, missing, unknown arguments |
| MS3010-3012 | Implementations |
| MS3020, MS3021 | Sharing, hashing |
| MS3030, MS3040, MS3050, MS3060 | Captures, recursion, exhaustiveness, mutation |
| MS3070, MS3080 | Numeric literals, generic inference |
| MS4000 | Lowering |

Rules are defined by [type checking](../../contributing/compiler/frontend/type-checker.md) and [scope and capture checking](../../contributing/compiler/frontend/scope-checker.md).
