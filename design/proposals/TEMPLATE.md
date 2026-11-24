# Feature name

<!-- Copy to design/proposals/<kebab-name>.md. Delete every comment and every
     section that does not apply. Target 60 to 100 lines; see README.md. -->

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

## Proposed design

<!-- The rule, stated once. Short `.ms` examples that pass `ms check` (accepted, and
     rejected with the exact diagnostic). Semantics for ownership, errors,
     cancellation, and edge cases, one bullet each. -->

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
