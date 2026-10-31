---
name: simplify
description: Simplify Manuscript code, APIs, design, or examples by removing duplicated behavior, unnecessary work, mixed responsibilities, and special cases. Use for requests to simplify, reduce complexity, clean up layers, or make code easier to follow.
---

# Simplify

When no area is named, simplify the current task's changes. For a broader
request, survey the requested area before choosing changes.

Use [manuscript-change](../manuscript-change/SKILL.md) for contract tracing,
domain checks, and durable lessons. Read the
[cleanup lessons](../../wiki/repository/repository-cleanup-must-remove-duplicated-work-and-layers.md)
and [architecture](../../documentation/contributing/architecture.md).

## Find the complexity

Trace a representative operation through callers and tests. Look for duplicated
behavior, repeated traversal or conversion, forwarding layers, mixed ownership,
special cases, and examples with unnecessary prerequisites. Group findings by
behavior and prioritize concrete benefits with manageable risk.

Show what disappears: two implementations become one owner, a source-only command
skips lowering, or an example loses an unrelated domain model. A smaller file
tree or line count alone does not establish simpler behavior.

## Choose the smallest coherent change

- Prefer deletion, direct calls, and existing checked facts or language
  mechanisms. Add a helper or layer only for demonstrated reuse or a clear
  responsibility.
- Give shared behavior one natural owner while preserving semantic differences.
  Buffered and streaming operations may share accounting but have different
  resource lifetimes. Similar syntax alone does not justify an abstraction.
- Inspect implementation paths as well as file organization. Check dependency
  boundaries before moving responsibilities; splitting files alone may leave
  duplicate work intact.
- Compare language/API alternatives with small source examples and fewer rules
  to remember. Use [language-design-taste](../language-design-taste/SKILL.md)
  for current choices, flat control flow, and generated-code performance goals.
- Simplify an example's scenario before adding helpers or types. Follow
  [documentation](../documentation/SKILL.md) for authoring and
  [documentation](../documentation/SKILL.md) for a broad redesign.

For a broad restructure, new representation, layer, or pass, follow the proposal
and independent skeptical review requirement in
[AGENTS.md](../../AGENTS.md#shared-guidance-and-checks) before implementation.
Local cleanup does not need this process.

## Preserve the contract and finish the removal

Behavior stays the same unless the user requested a behavior or design change.
For a requested behavior change, state the changed contract and migration.
Complete the manuscript-change contract trace, update affected consumers, and
remove superseded paths. Search again to verify the old implementation is gone.

Exercise the same observable cases before and after. Compare generated output
when unchanged lowering is the claim; measure performance when claiming speed
or allocation savings. Guidance-only edits need the
[catalog checks](../README.md#maintain-the-catalog).

Report the complexity removed, supporting checks, and remaining limitations.
Keep the completion claim within the area actually inspected and changed.
