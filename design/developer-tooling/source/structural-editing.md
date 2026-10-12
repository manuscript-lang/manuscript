+++
title = "Structural edits and revision guards"
weight = 110
+++

# Structural edits and revision guards

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Structural editing changes a program entity, such as a function or a resolved symbol. For example, a rename follows references to that symbol instead of replacing every matching word. Revision guards ensure the source has not changed since the edit was prepared.

The compiler exposes typed syntax, symbol references, effect summaries, scope/capture/sharing checks, and control flow. Operations include replacing a function, renaming a symbol, and adding a match case.

## A guarded edit

1. Resolve the entities to change and record revisions for every source/configuration input read, including `ms.toml` and referenced modules.
2. Prepare all affected files together. Renames follow symbol identity rather than matching text spellings.
3. Parse, resolve, and check the proposed program before writing.
4. Recheck every revision guard. A stale input or validation failure rejects the entire edit with zero writes.
5. Apply the accepted edit as one transaction; report success only when all intended files are updated.

For example, a cross-file rename is stale when a referenced file changes, even if the file containing the declaration did not. The tool must reread and prepare a new edit.

The wire schema and recovery from I/O failure or process interruption still need definitions. The implementation must provide recovery before claiming transactional multi-file edits.

See [typed compiler facts](../../compiler/frontend/typed-ir.md) and [structured diagnostics](diagnostics.md).

[Previous: Canonical formatting and generated views](../source/formatting.md) · [Next: Readable and structured diagnostics](../source/diagnostics.md)
