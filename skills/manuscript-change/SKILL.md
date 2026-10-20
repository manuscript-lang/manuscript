---
name: manuscript-change
description: Implement or review Manuscript language, standard library, runtime, compiler, documentation, or developer tooling changes against their full observable contract, and record durable lessons.
---

# Manuscript changes

Read [the expert protocol](../../.experts/README.md), then select relevant files from [the expert index](../../.experts/index.yml) by task meaning and affected paths. Apply [language design taste](../language-design-taste/SKILL.md) for design choices.

Select domain workflows from [AGENTS.md](../../AGENTS.md#domain-skills): language design, compiler (including syntax and parsing), runtime (including the standard library), tooling, documentation, and repository maintenance. Read only the relevant skills, adding another when the contract trace reaches it. They provide concrete entry points and checks; this skill owns the common change workflow.

## Establish the contract

Use the user's latest direction and the relevant canonical design pages to identify the behavior being changed. Compare them with the checkout's implementation and tests. When work depends on a newer decision or another branch, establish what is available before implementing against it; report a material mismatch. A proposal in an old conversation is not an accepted rule.

State a small observable example: what source is accepted, rejected, or behaves differently, and why. For design-only work, specify the rule and its acceptance cases without claiming implementation.

## Trace the change

Behavior is implemented in `crates/`; run `make conform-rust` when a change can alter observable behavior ([Rust toolchain](../../documentation/contributing/rust-toolchain.md)).

Follow the behavior through the surfaces it actually reaches. A language change can reach syntax, parsing, checking, lowering, runtime dispatch, diagnostics, formatting, navigation, completion, examples, and conformance. A standard API change can reach source declarations, native bindings, implementations, editor information, and generated reference pages. Identify the applicable surfaces before editing; a keyword search alone cannot discover aliases or related helper APIs.

For removal, inventory the construct's syntax, exported helpers, native bindings, examples, and generated artifacts. Use the user's requested removal scope to decide whether historical or rejection examples belong. For renaming, include public spelling, diagnostics, editor metadata, and links. Search again after regeneration to establish that the old surface is gone wherever required.

Keep each rule in its canonical design page and each standard signature in Manuscript source. Update consumers and regenerate derived output through the existing generator. Teach the changed behavior with a small example that uses only concepts already introduced.

## Establish evidence

Choose checks from the repository's current build files and CI. Language behavior needs source-level acceptance/rejection and native execution where runtime semantics change. Lifetime work needs observable cancellation and close behavior. Documentation examples need their displayed commands exercised; generated references need freshness checks and the book needs link/build validation. Run the checks applicable to the change and report any that could not run.

A review follows the same contract trace: passing tests do not establish that every requested surface changed. Report concrete gaps with the source rule and affected behavior. Distinguish implemented behavior, design decisions, and remaining work in the result.

## Record durable lessons

When the work yields reusable evidence or a correction, or the user asks to learn from previous interactions, close the loop using [the expert protocol](../../.experts/README.md) for routing, authority, and the entry format. A routine edit need not manufacture a lesson.

1. Read the relevant expert entries and the evidence from the work. For historical backfills, inspect actual user messages, changes, and checks; chat titles and assistant completion reports are discovery aids, not proof. Follow corrections through to the latest decision.
2. Identify what would change a future implementation or review: a non-obvious constraint, an accepted or rejected choice, a failure mechanism, or a check that caught a regression. Separate an explicit decision from verified behavior and a hypothesis; keep uncertainty as an open question only when it affects future work.
3. Put prevention in the strongest home. Observable regressions belong in behavioral tests; deterministic drift in the existing check or generator; exact semantics in canonical design; terminology in the glossary. The expert entry keeps the reason, evidence, and trigger for reaching that home. Change a workflow skill only when the lesson changes the workflow, and a taste preference only when the user's direction supports generalizing it.
4. Update the closest existing entry in place, merging repeated evidence and replacing superseded guidance. A newer explicit request can supersede a remembered decision before it ships: record the direction, link the request, and state what still needs checkout verification. Add an expert and index route only when a distinct domain needs one. Keep memory changes reviewable alongside the implementation; during read-only reviews, report proposed updates instead of editing.

Update catalog routes and both discovery directories when a skill is added, renamed, or removed. Finish when the next agent can find the lesson, tell what establishes it, and perform a concrete verification.

Completion includes the applicable contract surfaces, supporting checks, and any durable lesson discovered by the work.
