# Diagnostic sub-codes

## Summary

- Codes such as `MS3012` group many messages, so a tool cannot tell members of a family apart by code (#1541).
- Proposed: keep the family code and add a stable sub-code (`MS3012.1`) per message kind, reported in `--json` and explained by `ms guide <code>`.
- Cost: a table of message kinds in `crates/ms-syntax/src/diag.rs`, one entry per distinct cause, and a golden test that fails when a message has no kind.
- Decision requested: sub-codes (recommended), one code per message, or keep families.

## Status

Approved 2026-10-27 (Chinmay: "good to go for 1541"). Stage 1 implemented as a table of cause kinds in `diag.rs` (`KINDS`, `kind_for`), matched by cause text within the family, instead of kinds at every emit site; `--json` gains `subcode`, `ms guide MS3000.1` explains it, and `ms-conform` ignores the additive key. Checked against `origin/main` at `5f28e5d0`. Direction in #1541: fold the explanation into an existing command, not a separate `ms explain`. Verified: `ms guide <code>` already does this (`explain_codes` in `crates/ms-cli/src/commands.rs`), so no new command is needed.

## Problem

- Verified: the code is derived from the message text (`code_for` in `crates/ms-syntax/src/diag.rs`), by phase and then the first substring that matches (`"literal"`, `"immutable"`, `"expected "`). Any rewording of a message can silently move it to another family, and unmatched messages fall to the phase default (`MS3000`).
- `ms guide MS3012` can only give the family repair, because the code cannot say which cause occurred.
- Non-goals: renumbering existing family codes, or changing message wording.

## Design

- A sub-code is the family code plus a numeric suffix: `MS3012.1`. The family code stays valid for `ms guide MS3012`, and `ms guide MS3012.1` prints the repair for that cause.
- Checker sites that emit a message name its kind explicitly (an enum or constant next to the call), replacing substring matching. The kind table lives in `diag.rs` with the explanation text.
- `--json` diagnostics gain `"subcode"` beside `"code"`. Text output is unchanged.
- A golden test fails when a diagnostic reaches output without a kind, so new messages cannot fall back to a family silently.
- Stability: a sub-code is never reused for a different cause; a removed cause retires its number.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` `diag.rs` | kind table, `subcode`, `explain` accepts sub-codes | unit test: every kind has an explanation |
| `crates/ms-check`, `ms-lower`, parser | emit kinds at message sites | golden corpus asserts a kind per diagnostic |
| `crates/ms-cli` | `ms guide <subcode>`, JSON field | CLI test |
| docs, LSP | document the field; LSP `code` carries the sub-code | existing diagnostics tests |
| Runtime, lowering ABI | unchanged | none |

## Alternatives

- Do nothing: agents keep matching message text, which is the fragility described above.
- One code per message: highest precision, but the code space grows with every wording change and `MS3xxx` stops being a rule family.
- Sub-codes derived by hashing the message: unstable under rewording; rejected.

## Staging and verification

- Stage 1: kind table and sub-code in `--json` for the type phase, behind the golden coverage test. Stage 2: remaining phases and `ms guide`. Each stage passes `cargo nextest run --workspace` and `make conform`.

## Open questions

- Sub-code or one code per message? Recommend sub-codes; it preserves existing family codes users and docs already cite.
