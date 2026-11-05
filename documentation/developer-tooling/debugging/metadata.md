+++
title = "Inspect checked source"
weight = 118
+++

# Inspect checked source

Use `ms inspect` when you want a script or agent to work with declarations, types and call sites from checked code. For reading the same program visually, use an [interactive code map](../implementation.md#interactive-code-map).

## Save a snapshot

With `hello.ms` from [Understanding effects](../source/effects.md), run:

```sh
ms inspect hello.ms -o inspection.json
```

The command succeeds silently and writes a format-2 JSON document. It checks source without running the program or linking an executable. The `entities` array contains this declaration (selected fields shown):

```json
{
  "id": "hello.ms#fn#main",
  "kind": "fn",
  "name": "main",
  "type": "fn() Int",
  "exported": true,
  "effects": ["read", "unknown"]
}
```

Use the entity ID to follow `calls`: the call owned by `hello.ms#fn#main` targets `print` in the standard library. The snapshot also includes library entities; the diagram and review tools keep those implementations behind boundary leaves so a project view stays focused.

## Read positions and identities

- `sources` records source paths and hashes; `build_id` identifies the checked source set. Keep the source snapshot with an inspection if you plan to revisit its positions later.
- Entities have deterministic IDs, checked types, visibility and conservative effects. Local bindings also carry generated checker identities and types.
- `calls` includes explicit calls and implicit cleanup. `statements` gives statement-header spans for navigation.
- Spans use half-open `start`/`end` byte offsets in the original source, with one-based line and UTF-8 byte column. Statement-header ranges exclude line terminators. These are source positions, not machine-code addresses; CRLF files retain their original byte offsets.

Treat [effect summaries](../source/effects.md) as conservative descriptions of reachable behavior. Inspection does not execute branches, tests or external operations.

## Follow a running program instead

Build with `--build-type Debug` when you want unoptimized code for stepping. Native builds keep frame pointers and DWARF line tables that map machine addresses back to `.ms` lines. See [profiling and native debugging](debugger-integration.md) to capture a profile or stop at a source line.
