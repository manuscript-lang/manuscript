+++
title = "Project configuration"
weight = 1
+++

# Project configuration

Use a project when your program grows beyond one file, needs tests beside its source, or bundles assets. The `ms.toml` at its root tells `ms` where to find those inputs. Each `.ms` file is one module.

## A project manifest

Create a project, then check its generated source and test:

```sh
ms init store
cd store
ms check ms.toml
```

The check prints:

```text
Checked ms.toml (2 modules)
```

`init` creates `ms.toml`, `src/main.ms`, `test.ms` and a `.gitignore` excluding the local build cache. Run the following examples from `store`. Keep the generated manifest for the exercises below. The following configuration illustrates aliases for a larger project; add those entries only after creating the directories and files they name:

```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[aliases]
"@domain" = "./src/domain"
"@customers" = "./src/domain/customers.ms"
```

- `name` names the project; `source` is its source directory.
- `entry` is the executable entry file. Omit it for a library; an empty or invalid entry is an error. There is no default.
- All manifest paths resolve relative to the directory containing `ms.toml` (the entry is not relative to `source`).
- Only `[project]`, `[aliases]` and `[embed]` exist. Unknown or duplicate tables and keys are rejected. Values are double-quoted strings; `#` starts a comment.
- Application modules are found by following imports from the entry, not listed in the manifest.
- The compiler supplies the prelude and version-matched `@std` modules. To reuse other Manuscript source today, use [copied dependencies](#library-projects-and-copied-dependencies); `ms` does not fetch third-party packages.

## Split a program into modules

A manifest chooses the project boundary; imports describe dependencies inside it. To move pricing logic out of `main`, create `src/pricing.ms` with this complete module:

<!-- manuscript-artifact: {"kind":"support","filename":"pricing.ms"} -->
```manuscript
export fn total(price: Int, quantity: Int) Int:
    return price * quantity
```

Replace `src/main.ms` with:

<!-- manuscript-example: {"mode":"run","build_files":{"pricing.ms":"export fn total(price: Int, quantity: Int) Int:\n    return price * quantity\n"},"stdout":"36\n"} -->
```manuscript
import total from "./pricing.ms"

export fn main() Int:
    print(total(price: 12, quantity: 3))
    return 0
```

Run `ms run ms.toml` from `store`. It prints `36`. The import is relative to the file containing it, so `./pricing.ms` means `src/pricing.ms`, regardless of the shell's working directory. `export` makes `total` available to another module; leaving it off makes this import an error. You do not add a list of modules to the manifest.

An alias makes frequently used paths shorter without changing visibility. For example, add `"@pricing" = "./src/pricing.ms"` under `[aliases]`, then use `import total from "@pricing"`. Both imports identify the same module; an alias does not copy code or install a dependency. Use directory aliases when several modules share a prefix, and file aliases for one module. The exact rules are under [resolving an import](#resolving-an-import).

Keep `ms check ms.toml` in your workflow as the source tree grows. Running the entry checks what that program imports; checking the project also finds mistakes in a module that no running program uses yet.

## Embedded files

`[embed]` bakes a directory into the program. Each key is an import name written like an alias, and each value is a directory below the project root:

```toml
[embed]
"@assets" = "./assets"
```

Create `assets/message.txt` containing `hello from assets` followed by a newline. Replace `src/main.ms` with this complete program:

<!-- manuscript-example: {"mode":"run","build_files":{"ms.toml":"[project]\nname = \"embedded-example\"\nsource = \".\"\nentry = \"example.ms\"\n[embed]\n\"@assets\" = \"assets\"\n","assets/message.txt":"hello from assets\n"},"stdout":"hello from assets\n"} -->
```manuscript
import files from "@assets"

fn message() String!:
    let tree = files()
    let bytes = try tree.read("message.txt", none)
    let text = try bytes.decode_utf8().ok_or()
    return ok(text.trim())

export fn main() Int:
    let result = message()
    if let text = result:
        print(text)
        return 0
    print("Could not read the embedded message")
    return 1
```

```sh
ms run ms.toml
```

```text
hello from assets
```

Embedding makes bytes available without a separate asset directory at runtime. It does not prove that a requested path exists or that its contents are UTF-8. `read` returns a `Result`; decoding returns an `Optional`, which `ok_or()` converts to a `Result`. The helper propagates either failure with `try`, and `main` chooses the message and exit status. Change the requested path to `missing.txt` to take that failure path: the program prints `Could not read the embedded message` and exits 1. See [Results](../../core-language/errors/results.md) for preserving a more specific error.

- `import files from "@assets"` imports a module that `ms` generates from the directory when the project loads. Write the name alone: `"@assets/x.ms"` is an error.
- `files()` returns an `EmbeddedTree` from `@std/os/tree.ms`, so `read`, `children` and `walk` work as they do on a `host_tree`. Making it costs one map entry per file; `read` copies only the file it returns.
- Paths in the tree are relative to the directory and use `/` on every platform. Entries are listed in byte order. Hidden files are included.
- Symbolic links, names that are not valid UTF-8, and names that differ only by letter case are errors. A file may be at most 16 MiB and a directory 64 MiB in total.
- The files are stored in the program as raw bytes in read-only data, alongside the program code and lookup metadata. An edited, added or removed file rebuilds the program.
- A name cannot also be an alias.

## Commands and module discovery

| Command | Behavior |
| --- | --- |
| `ms check <ms.toml>` | Check all source modules and discovered tests; validate entry when present |
| `ms build <ms.toml>` | Check, lower to MIR, generate native object code, and link the executable; requires entry |
| `ms lint <ms.toml>` | Check and lint reachable modules; libraries include all source modules and discovered tests |
| `ms test <ms.toml>` | Execute tests from entry and discovered test files; libraries include all source modules too |

`ms check ms.toml` checks every `.ms` file below `project.source`, including modules the entry does not import, plus `test.ms`, `*_test.ms`, `bench.ms`, and `*_bench.ms` anywhere below the project root. It never runs `main` or tests and needs no native toolchain. Text output reports the number of modules checked.

Discovered source filenames and visited directory names must be valid UTF-8. Invalid names report a resolution error with a rename remedy; discovery never replaces them with another path. Excluded files and directories keep their existing discovery rules.

- Discovery skips hidden directories (such as `.ms-cache`), `vendor`, `node_modules`, and directory symlinks. Entries and imports are always followed.
- Files outside the source directory are checked only if imported, the entry, or discovered test/benchmark files.
- `ms check file.ms` checks that file and its imports only.
- `check` and `lint` also take several targets; see [analysis input selection](../implementation.md#selecting-independent-analysis-inputs).

## Library projects and copied dependencies

A library needs no placeholder `main`:

```toml
[project]
name = "graph"
source = "src"
```

`check`, `lint`, and `test` include every source module and discovered test. `run`, `build`, `emit`, and `profile` need an executable entry: add `entry = "src/main.ms"` and export `fn main() Int`.

To share library code today, copy its sources into each consuming project, for example `src/graph/`, and use relative imports or an alias:

```toml
[aliases]
"@graph" = "src/graph"
```

Keep the copy under version control and record the upstream URL, exact revision, SHA-256 checksums, and license notices. Update it deliberately. The compiler does not fetch packages or verify those checksums, and copied content is not pinned. An alias to a sibling project or an external symlink is rejected.

## Resolving an import

Imports name an exported symbol and a path. These are reference declarations illustrating path resolution, not a standalone program; they assume the two modules and exported types exist:

<!-- manuscript-artifact: {"kind":"import"} -->
```manuscript
import CustomerId from "./domain/customers.ms"
import Order from "@domain/orders.ms"
```

For an import in `src/main.ms`, the first path resolves to `src/domain/customers.ms`. The second expands `@domain` and resolves to `src/domain/orders.ms`.

| Path form | Resolves to |
| --- | --- |
| `./` or `../` | Relative to the importing file's directory |
| `@std/...` | The compiler's standard library; the `@std` alias key is rejected |
| `@name/...` | Through the project's aliases; keys are `@` plus one identifier |

- A directory alias matches a whole first segment (`@domain` does not match `@domain_extra`) and appends the rest; alone it selects no module.
- A file alias selects exactly its target `.ms` file and accepts no extra segments.
- Alias targets are relative to `ms.toml`; aliases do not expand other aliases.
- Direct paths and paths under directory aliases must include `.ms`. Extensions are never inferred and directory entry files are never searched.
- Bare module names and absolute paths are not import forms. Use `/` separators.

`[aliases]` is optional. Missing source or entry files, invalid or unknown aliases, and unresolved imports are compile errors, as are missing or internal symbols, wildcard imports, and cyclic dependencies.

## Module identity and configuration scope

Paths are normalized and symlinks resolved to one canonical file identity per build, so importing a file by relative path, file alias, or directory alias yields one module and cycle checks cannot be bypassed. Build metadata records paths relative to the project root.

- Application paths, source directories, and aliases must resolve inside the project root after symlink resolution; escapes are compile errors.
- `@std/...` resolves only inside the pinned standard library, which cannot import application modules.
- Changes to source roots, entry, aliases, or the standard-library distribution change the module graph and build cache identity.

See [module exports and imports](../../core-language/modules/declarations.md), [the compilation pipeline](../../contributing/compiler/frontend/pipeline.md), and [build caches](incremental-compilation.md).
