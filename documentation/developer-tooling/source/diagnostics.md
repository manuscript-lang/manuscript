+++
title = "Diagnostics"
weight = 2
+++

# Diagnostics

A diagnostic explains a problem and points to the source that caused it. Human-readable output helps you fix the code; structured output lets editor tools locate the same problem.

Each diagnostic has a stable rule code, a readable message, and a primary source position. When its exact extent is known, it also carries an exclusive end position. Source coordinates follow the [metadata span contract](../debugging/metadata.md).

## Message shape

A message names the cause first, then a fix after a semicolon: `<cause>; <fix>`. The cause keeps stable wording and states the offending name, type, or count; the fix is something to write or change, such as `did you mean 'count'?`, `add: import panic from "@std/faults.ms"`, `declare it with 'var x = ...' instead of 'let'`, or the list of valid arguments, members, cases, or exports. Rule codes classify only the text before the first `; `, so adding or rewording a fix never changes a code. A follow-on error that only restates an earlier one, such as `found <invalid>` after an unknown name, is not reported. A missing argument is reported at the call, naming the callee and parameter type. When adding a message, follow this shape and extend the matching test in `pkg/checker/hints_test.go`, `pkg/parser/hints_test.go`, or `internal/cli/cli_test.go`.

## Explaining a violated rule

For example, a non-function argument to TaskGroup.start should identify the required callable type and source position. An invalid `with` initializer should identify the missing concrete implementation, contract operation, or generic-bound proof. A missing match alternative or unnamed argument should identify the relevant declaration and call-site location. Runtime closed-resource errors carry operation and source locations separately from static diagnostics.

`ms check file.ms --json` emits `{"format": 1, "diagnostics": [...]}`. Each diagnostic has `code`, `phase`, `message`, and `position` with `file`, one-based `line`/UTF-8 byte `column`, and original-byte `offset`. Empty results use `[]`. CRLF normalization preserves original offsets.

Check and lint can report several independent inputs in one document. See
[analysis selection and aggregation](../implementation.md#selecting-independent-analysis-inputs)
for collection paths, ordering, partial failures, and project boundaries.

Optional `end` uses the same coordinate fields and marks the exclusive end of the diagnostic range. Parser token errors and failed import names provide this range; diagnostics without a known extent omit it.

An optional `fix` contains `position`, exclusive `end`, and `replacement`. Apply it by replacing that byte range in the original source snapshot, then check the edited file again. For `total += x`, the fix replaces `+=` with `= total +`. Automatic compound-assignment fixes are limited to bare variable targets with a single name or numeric operand. More complex operands, field receivers, string-match rewrites, and ambiguous imports receive prose guidance without a machine fix. Consumers must tolerate absent optional fields; the existing fields and `format: 1` remain unchanged.

Codes identify rule families: MS1000 grammar, MS1001 literals/text, MS1002 layout; MS2001 names/members, MS2002 modules; MS3000 general typing, MS3001 exact types/operators, MS3002–3004 duplicate/missing/unknown arguments, MS3010–3012 implementations, MS3020 sharing, MS3021 hashing, MS3030 captures, MS3040 recursion, MS3050 exhaustiveness, MS3060 mutation, MS3070 numeric literals, MS3080 generic inference; MS4000 lowering. Ranges for other checker errors and related-declaration spans remain a richer diagnostic revision. The rules being reported are defined by [type checking](../../contributing/compiler/frontend/type-checker.md) and [scope and capture checking](../../contributing/compiler/frontend/scope-checker.md).
