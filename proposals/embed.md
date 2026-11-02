# Embed files in the binary (`[embed]`)

## Summary

- Problem: a single-binary program that needs templates, fixtures or assets must read them from disk at run time or inline them as string literals (#2337).
- Change: an `[embed]` table in `ms.toml` maps an import name to a directory; the project loader turns that directory into a generated Manuscript module whose `files()` returns a `MemoryTree` (`@std/os/tree.ms`). No new syntax, type or runtime primitive.
- Decision requested: none. Chinmay chose the manifest route over a built-in (2026-11-02).

## Status

Implemented 2026-11-02 on main 09c89a2b; reviewed by an independent skeptic, whose findings are folded in below. Chinmay: "looks good" on the `ms.toml` table sketch.

## Problem

Go's `embed` ships files in the binary. `ms build` output must today read `./assets/page.html` from disk or carry the text as a literal.

```toml
[embed]
"@assets" = "./assets"
```

```ms
import files from "@assets"

export fn main() Int:
    let page = files().read("index.html", none).get()
    return page.length()
```

## Design

- `[embed]` keys follow `[aliases]`: `@name` to a directory path resolved against `ms.toml`. A key may not also be an alias. Unknown keys, a missing or non-directory target, and a path outside the project root are manifest errors with a remedy.
- `import files from "@assets"` resolves to a generated module. `resolve_import` checks `[embed]` before `[aliases]` and returns the virtual path `<root>/.ms-embed/assets.ms`; a suffix such as `@assets/x.ms` is an error. `Loader::load` generates the source instead of reading a file. A name in both tables is a manifest error.
- The source is `export fn files() MemoryTree`, which writes each file from a base64 string literal decoded with `@std/data/encoding.ms`.
- The directory is read when the module loads: entries sorted by name, `/` separators on every platform, symlinks, non-UTF-8 names and names that differ only by case rejected, files over 16 MiB each (64 MiB total) rejected. Hidden entries are included; the author keeps the directory clean.
- The generated module is a normal module: checked, lowered and linked like any other, so the bytes land in the binary's read-only data as string literals; nothing is read at run time and no runtime changes.
- `files()` decodes on each call and returns a fresh owned `MemoryTree`; callers keep it in a `let` for repeated reads. It is a read tree by convention (`MemoryTree` has write methods; an embedded tree changes only in memory).
- Cache: the build cache stamps files by mtime and size and never hashes source, so the generated module alone would go stale. `ms build` adds the embedded directory and every file below it to the cache inputs, and `cache::stamp` accepts directories so added and removed entries are noticed.
- Measured: a 3 MiB file builds and decodes in about 46 ms per `files()` call (prototype, main 09c89a2b).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/manifest.rs` | parse and validate `[embed]` | manifest error cases in the project tests |
| `crates/ms-driver/src/project/{embed,paths}.rs`, `load.rs` | resolve `@name` to a virtual module, walk the directory, generate its source | `project_project.rs`, `embed.rs` unit tests |
| `crates/ms-build/src/cache.rs`, `ms-cli/src/engine/build.rs` | stamp embedded inputs | edit, add and remove rebuild checked by hand |
| `tests/e2e/testdata/projects/embedded_files` | read text, binary and nested files, walk, NotFound | `ms test` |
| `documentation/developer-tooling/builds/project-configuration.md` | document `[embed]` | docs check |

Unchanged: checker, MIR, codegen, runtime, `stdlib/`.

## Alternatives

- Do nothing: assets stay on disk or in literals. Rejected by the owner's request for `embed` parity.
- A built-in `embed("path")` expression: needs a checker rule and a new constant form; rejected by the owner for the manifest route.
- Raw bytes in the object file via a new MIR constant: smaller binaries and no decode, but touches the checker, MIR and codegen. Revisit if the base64 cost shows in a measurement.

## Stages

1. Manifest table, generated module, e2e and docs, in one PR. The decode cost and compile time for a 5 MiB asset directory are measured and recorded in Status.

## Open questions

- Raw bytes in the object file would avoid the decode and the one-third growth; revisit if a measurement shows the cost matters.
