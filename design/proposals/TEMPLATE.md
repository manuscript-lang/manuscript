# Feature name

<!-- Copy to design/proposals/<kebab-name>.md. Delete every comment and every
     section that does not apply. Target 80 to 150 lines, most of it Detailed design; see README.md. -->

* Status: **Proposed** | **Approved** | **Implemented** | **Rejected** | **Withdrawn** (date, commit checked)
* Authors: [name](https://github.com/login)
* Implementation: PR links, or "not yet implemented"
* Issue: *if applicable* #NNNN
* Supersedes / Extracted from: *if applicable* [other-proposal](other-proposal.md)
* Direction: *if applicable* quote the owner decision that constrains this design, with its date

## Summary

<!-- Three bullets, 50 words at most in all: the problem, the change, the decision requested. -->

- Problem:
- Change:
- Decision requested:

## Motivation

<!-- The observable failure or cost, with one repro of at most 10 lines or one
     measurement (command, commit, number). Further cases: one bullet each, with a
     pointer to the test or fixture. Non-goals only if a reader would assume them. -->

## Proposed solution

<!-- The idea in the user's terms: one or two short `.ms` before/after examples that
     pass `ms check`, and why this beats the workaround. Not comprehensive. -->

## Detailed design

<!-- Enough for someone who is not the author to implement it without asking.
     Cover each that applies, as a subsection or bullet:
     - Syntax: grammar additions, with accepted and rejected `.ms` examples
       (`ms check` output pasted, including exact diagnostics and their mechanical fixes).
     - API: full stdlib declarations with doc comments, as they will appear in `src/stdlib/*.ms`.
     - Semantics: typing rules, ownership and moves, borrows, errors, cancellation,
       resource closing, concurrency, and evaluation order.
     - Edge cases: empty, nested, generic, shadowed, and error paths, one bullet each.
     - Lowering and runtime: what the checker, MIR, optimizer, and runtime do; data
       layout and any new invariant or ABI entry point.
     - Diagnostics and tooling: messages, lsp, fmt, lint, docs, agent skill.
     A diagram only where data flow, lifetimes, layout, or stage order matter. -->

## Fit with the language

<!-- Keep only the lines that apply; say "no change" in one line where it is true. -->

- **Memory model:** one owner, borrow by default, `.clone()` the only copy, no hidden copies. How does this follow it?
- **Agent ergonomics:** can a model write this correctly from the guide and the diagnostics alone? Name the error message and its mechanical fix.
- **Names and syntax:** reused names and constructs; any new keyword, type, or syntax and why nothing existing covers it.
- **Platforms:** Linux, macOS, and Windows behave the same. Name any platform-specific mechanism and its equivalent on the others.

## Measured benefit

<!-- Required for a perf, size, or compile-time claim and for any departure from
     convention. Before/after against the latest dated baseline in bench/perf/,
     many runs (median) or instruction counts, checked C where C is compared.
     Hypotheses are labeled as such. Omit for a pure correctness change. -->

## Components touched

| Component | Change | Test |
| --- | --- | --- |

## Compatibility

<!-- What existing programs, fixtures, stdlib, docs, and tooling (lsp, fmt, lint,
     skill) change. Is a migration or a diagnostic with a fix needed? -->

## Alternatives considered

<!-- Do nothing, the smallest version, and the real runner-up: one or two lines each
     with the evidence it lost. -->

## Stages

<!-- One line per stage with the check that gates it. Omit when there is one stage. -->

## Future directions

<!-- Related work deliberately left out, and why. Not a commitment. -->

## Open questions

<!-- Only where the language or user-visible behavior changes; each with a recommendation. -->
