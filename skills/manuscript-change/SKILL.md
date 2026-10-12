---
name: manuscript-change
description: Implement or review Manuscript language, standard library, runtime, compiler, documentation, or developer tooling changes against their full observable contract.
---

# Manuscript changes

Read [the expert protocol](../../.experts/README.md), then select relevant files from [the expert index](../../.experts/index.yml) by task meaning and affected paths. Apply [language design taste](../language-design-taste/SKILL.md) for design choices.

## Establish the contract

Use the user's latest direction and the relevant canonical design pages to identify the behavior being changed. Compare them with the checkout's implementation and tests. When work depends on a newer decision or another branch, establish what is available before implementing against it; report a material mismatch. A proposal in an old conversation is not an accepted rule.

State a small observable example: what source is accepted, rejected, or behaves differently, and why. For design-only work, specify the rule and its acceptance cases without claiming implementation.

## Trace the change

Follow the behavior through the surfaces it actually reaches. A language change can reach syntax, parsing, checking, lowering, runtime dispatch, diagnostics, formatting, navigation, completion, examples, and conformance. A standard API change can reach source declarations, native bindings, implementations, editor information, and generated reference pages. Identify the applicable surfaces before editing; a keyword search alone cannot discover aliases or related helper APIs.

For removal, inventory the construct's syntax, exported helpers, native bindings, examples, and generated artifacts. Use the user's requested removal scope to decide whether historical or rejection examples belong. For renaming, include public spelling, diagnostics, editor metadata, and links. Search again after regeneration to establish that the old surface is gone wherever required.

Keep each rule in its canonical design page and each standard signature in Manuscript source. Update consumers and regenerate derived output through the existing generator. Teach the changed behavior with a small example that uses only concepts already introduced.

## Establish evidence

Choose checks from the repository's current build files and CI. Language behavior needs source-level acceptance/rejection and native execution where runtime semantics change. Lifetime or concurrency work needs observable cancellation, close, and join behavior, plus relevant race coverage. Documentation examples need their displayed commands exercised; generated references need freshness checks and the book needs link/build validation. Run the checks applicable to the change and report any that could not run.

A review follows the same contract trace: passing tests do not establish that every requested surface changed. Report concrete gaps with the source rule and affected behavior. Distinguish implemented behavior, design decisions, and remaining work in the result.

When the work yields reusable evidence or a correction, use [change-memory](../change-memory/SKILL.md). Completion includes the applicable contract surfaces, supporting checks, and any durable lesson discovered by the work; a routine edit need not manufacture a lesson.
