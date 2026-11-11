+++
title = "Diagnostics"
weight = 2
+++

# Diagnostics

Use `ms check` while editing to find mistakes before running the program. A diagnostic tells you where the problem is, what rule failed and how to repair it.

## Follow a repair

Save this program as `count.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"3\n"} -->
```manuscript
fn main() Unit:
    var count = 2
    count += 1
    print(count)
```

```sh
ms run count.ms
```

```text
3
```

Change `var count` to `count := ...`, then run `ms check count.ms`. It exits with status 1 and points to the assignment on line 3. The diagnostic message is:

```text
cannot assign immutable binding count; declare it with 'var count = ...' instead of 'count := ...'
```

Here the intended repair is mechanical, so you can apply it and run again:

```sh
ms check count.ms --fix
ms run count.ms
```

The checker reports `ms: applied 1 fix in 1 file` and `Checked count.ms`; the program prints `3` again. Review applied edits before keeping them. When a repair needs a choice about the program's meaning, follow the explanation and edit the source yourself.

Each diagnostic also has a stable rule code and source position for editor and agent integrations. The same error is `MS3060` in `ms check count.ms --json`; the JSON includes the exact replacement range and `"replacement": "var"`.

## Message shape

Messages read `<cause>; <fix>`. The cause has stable wording naming the offending name, type, or count.

The fix says what to write, such as `did you mean 'count'?`, `add: import panic from "@std/core.ms"`, `declare it with 'var x = ...' instead of 'count := ...'`, or the valid arguments, members, cases, or exports. Codes classify only the text before the first `; `, and follow-on errors that restate an earlier one are not reported.

## Explaining a violated rule

A diagnostic names the violated rule and the declaration or call site involved. Runtime closed-resource errors carry operation and source locations separately.

## JSON diagnostics

`ms check file.ms --json` emits `{"format": 1, "diagnostics": [...]}`. Each diagnostic has `code`, `phase`, `message`, and `position` with `file`, one-based `line`/UTF-8 byte `column`, and original-byte `offset`. Empty results use `[]`. CRLF normalization preserves original offsets. `--with-text` adds `text` with the `stdout` and `stderr` the command prints without `--json`, so one run yields both. With several inputs, `--each` reports each as its own result, `{"results": [{"target", "exit_code", "document"}]}`, from one standard-library load.

Several inputs share one document; see [analysis selection](../implementation.md#selecting-independent-analysis-inputs).
Each diagnostic's `position`, `end`, and `fix` boundaries use the same source-path spelling, including paths relative to the invocation directory for collection inputs.

- Optional `end` has the same coordinate fields (exclusive). Parser token errors and failed import names provide it.
- Optional `fix` has `position`, exclusive `end`, and `replacement`: replace that byte range in the original snapshot, then recheck. Redundant prelude imports, misspelled names, members, labels and types with one `did you mean` candidate, unresolved standard names and the `Decimal` literal import (an `import` inserted at the top of the file), `Some`/`Ok`/`Err`/`True`/`null`/`this` habits, assignment to a `:=` binding (`:=` becomes `var`), and `Case()` on a nullary case, Int values used as Float (`.to_float()`, or `3.0` for a literal), Int, Float and Bool values used as String (`"{value}"`), and `ms lint` unused imports (MSL102, the name with its separator, or the whole statement) carry one; string-match rewrites, ambiguous imports and ownership errors get prose only: a machine-applied `.clone()` would hide the design choice and cost time and memory. `ms check --fix` and `ms lint --fix` apply these edits in place (skipping overlaps), then report what remains.
- Optional `subcode` (`MS3000.1`) names the cause within the family `code`; it is absent for messages without a known cause. Sub-codes are never renumbered or reused.
- Consumers must tolerate absent optional fields.

| Code | Family |
| --- | --- |
| MS1000, MS1001, MS1002 | Grammar, literals/text, layout |
| MS2001, MS2002, MS2003 | Names/members, modules, redundant canonical prelude imports |
| MS3000, MS3001 | General typing, exact types/operators |
| MS3002-3004 | Duplicate, missing, unknown arguments |
| MS3010-3012 | Implementations |
| MS3021 | Hashing |
| MS3030, MS3040, MS3050, MS3060 | Captures, recursion, exhaustiveness, mutation |
| MS3070, MS3080 | Numeric literals, generic inference |
| MS4000 | Lowering |

`ms explain <code>` prints a code's or sub-code's family and usual repair (`--json` for structured output), for example `ms explain MS3000.1`.

For the language rules behind a diagnostic, start with [variables](../../core-language/basics/bindings.md) and [values and references](../../core-language/types/references.md).
