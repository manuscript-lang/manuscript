---
name: author-proposal
description: Write a Manuscript design proposal in technical language with sectioned bullets, touched components and per-component changes, examples, diagrams, a simplification pass, and alternatives including doing nothing.
---

# Author a proposal

Use whenever you write or revise a design proposal (`proposals/*.md`), including the short proposal AGENTS.md requires before a cross-package change. Follow [manuscript-change](../manuscript-change/SKILL.md) for contract tracing and [language-design-taste](../language-design-taste/SKILL.md) for design choices. Read one or two existing proposals in `proposals/` for shape before drafting. Link a proposal that is a skeptical-review target to the reviewer's findings once it has them.

## Style

- Technical language: name crates, files, functions, types, MIR ops, and ABI details exactly (`crates/ms-check/src/ownership/modes.rs`, `msrt_task_spawn`). No marketing words, no narrative, no "we feel".
- Structure everything as headed sections with bullet lists. A paragraph is acceptable only for one connecting sentence. Prefer one fact per bullet.
- Every claim is evidenced or labeled: measured (command, commit, number), verified in source (`file:line`), or hypothesis. State what is not yet measured.
- No walls of text: bullets of one line (two at most), no paragraph longer than two sentences, a section the reader can scan in seconds. Lead each section with its conclusion. Put detail in a table, example, or diagram instead of prose.
- Short. Cut background the reviewer already knows; link canonical docs instead of restating rules.

## Required sections

1. **Status**: proposal, approved, or implemented; date; checkout or commit verified against; the user's direction being implemented, quoted with date.
2. **Problem**: observable failure or cost, with a minimal `.ms` repro and exact output, or a measurement. Who is affected.
3. **Goals and non-goals**: bullets. Non-goals prevent scope creep and name what stays unchanged.
4. **Design**: the rule, stated once. Include:
   - **Syntax / API**: `.ms` examples for accepted and rejected source, with the exact diagnostic text or code. Show before and after for changed programs. Examples must run or be marked illustrative.
   - **Semantics**: ownership, evaluation order, cancellation, errors, edge cases; each as a bullet with an example where the rule is not obvious.
   - **Diagram** (see below) whenever data flow, lifetimes, layout, or stage ordering matter.
5. **Components touched**: a table or bullet per component with *what changes*. Cover every surface the change reaches (see manuscript-change): syntax/parser, checker, lowering/MIR, codegen (Cranelift, LLVM), runtime (`ms-rt`) and ABI, stdlib `.ms` and `bindings.json`, formatter, lint, LSP/VS Code, CLI, docs, conformance and e2e tests. State "unchanged" for components a reader would expect to change.

   | Component | Change | Risk / test |
   | --- | --- | --- |
   | `crates/ms-check` | new `ref` result rule, MS#### diagnostic | conformance reject cases |

6. **Examples**: at least one end-to-end program, and one rejected program with its diagnostic. Prefer realistic code over toy names.
7. **Alternatives**: each with why it was set aside, including **do nothing** and the smallest possible version. Cite evidence, not taste.
8. **Evidence and cost**: measurements or code removed, and what the change adds (binary size, instructions, API surface, concepts a learner must hold).
9. **Staging and verification**: ordered stages that each land green, the check per stage (`make conform`, a benchmark, a test name), and the go/no-go gate.
10. **Open questions**: decisions for the owner, each with options and a recommendation. Only items that change the language or user-visible behavior.

Omit a section only by writing one line saying why it does not apply.

## Diagrams

- Use fenced `mermaid` (flow, sequence, state) or fixed-width ASCII for layouts. Use a diagram for: pipeline or stage changes, ownership/borrow lifetimes, memory or ABI layout, task/cancellation sequences, component dependency changes.
- Show before and after when the change rewires something. Label each edge with what flows across it. Keep to the components the proposal touches.
- Do not add a diagram that restates a bullet list.

## Simplification pass (before review)

Ask, and answer in the proposal's Alternatives or Design section:
- What can be removed? List each new concept, keyword, flag, type, runtime entry point, and pass, and justify or delete it.
- Can an existing mechanism cover the case (existing syntax, stdlib function, check, runtime path)? Show why not.
- Can the first version be smaller (one stage, one platform path, no new syntax) and still prove the benefit?
- Does it add a second rule where one rule would do (see the `ref` proposal's place-projection decision)? Collapse to one.
- Will a user or agent learn it from the guide in one example? If not, simplify.

Rework the design until each remaining piece has a stated reason. Record what the pass removed.

## Before handing off

- Verify every `file:line`, command, and snippet against the checkout; run repros.
- Check parity: behavior and tests must hold on Linux, macOS, and Windows; never propose disabling a test on a platform.
- Run the skeptical review required by [AGENTS.md](../../AGENTS.md) on the finished draft, give the reviewer the proposal rather than your conclusion, and revise. Record the review outcome in Status.
- Run `make repo-check`; keep `match` flat in examples.
