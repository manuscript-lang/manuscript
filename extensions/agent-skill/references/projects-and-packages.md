# Projects, ms.toml and packages

A project is a directory with an `ms.toml`. Use one when a program grows past a file, needs tests beside the source, or uses packages. `ms init <name>` creates `ms.toml`, `src/main.ms`, `test.ms`; `ms init --lib <name>` creates a library. Run commands on the manifest: `ms check ms.toml`, `ms run ms.toml`, `ms test ms.toml`, `ms build ms.toml -o prog`. `ms.toml` is TOML: strings are quoted, lists are arrays of strings, keys starting with `@` are quoted.

## The manifest

<!-- manifest: application -->
```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[aliases]
"@domain" = "./src/domain"
"@customers" = "./src/domain/customers.ms"
```

- Only `[project]`, `[workspace]`, `[aliases]`, `[embed]`, `[dependencies]` and `[effects]` exist; an unknown or duplicate table or key is an error.
- `name` names the project. `source` is the source directory. `entry` is the executable entry file; omit it for a library (`run` and `build` then need one; there is no default). `version = "1.2.3"` (optional, no leading `v`) is for packages used as dependencies.
- Every manifest path is relative to the directory holding `ms.toml`. `entry` is not relative to `source`.
- Modules are found by following imports from the entry; they are not listed. `ms check ms.toml` checks every `.ms` file below `source` plus `test.ms` and `*_test.ms`.
- A library is a manifest with no `entry`; `check`, `lint` and `test` include every source module.

## Imports

| Path form | Resolves to |
| --- | --- |
| `./x.ms`, `../x.ms` | relative to the importing file |
| `@std/data/json.ms` | the standard library |
| `@domain/orders.ms` | a directory alias plus the rest of the path |
| `@customers` | a file alias, exactly that file |

```manuscript
import Order from "@domain/orders.ms"
import Config, open from "@pg/conn.ms"
import helper from "./util.ms"
export fn total(order Order) Int => order.cents
```

Always write the `.ms` extension; extensions and `index` files are never inferred. A name must be `export`ed to be imported: `export fn`, `export type`. `import Order, total from "@domain/orders.ms"`. No wildcard imports, no cycles, no absolute paths.

## Embedded files

`[embed]` bakes a directory into the program. The key is an import name, the value a directory:

<!-- manifest: embed -->
```toml
[project]
name = "site"
source = "./src"
entry = "./src/main.ms"

[embed]
"@assets" = "./assets"
```

`import files from "@assets"`, then `files().read("message.txt", null)` reads from the tree (see `@std/os/tree.ms`). Write the name alone: `"@assets/x.ms"` is an error. A name cannot also be an alias.

## Packages

A package is a library project in a git repository. Add one with `ms add <url> --version 1.2` (or `--tag v1`, or `--sha <40 hex digits>`); it writes the dependency into `ms.toml` and installs it. `ms remove @name` takes it out, `ms install` resolves everything and writes `ms.lock` (commit it), `ms install --update @name` picks the version again. `check`, `build`, `run`, `test` and `lint` never use the network.

<!-- manifest: package-user -->
```toml
[project]
name = "orders"
source = "./src"
entry = "./src/main.ms"

[dependencies]
"@pg" = { url = "https://github.com/manuscript-lang/ms-pg.git", version = "1.2" }

[effects]
"@pg" = ["std.net.*", "std.clock.read", "std.random.read"]
```

- A dependency is a table with `url` and exactly one of `version` (a semver requirement like `1.2`, `^1.2`, `~1.2.3`, `=1.2.3`), `tag` or `sha`. No `>=`, `<` or comma ranges.
- `[effects]` lists, per dependency, the effects the project allows it (`std.net.*`, `std.fs.read`); a package that declares an effect you did not allow is rejected.
- Import from a package like an alias: `import Config, open from "@pg/conn.ms"`; the path is under the package's `source`. A package's own dependencies are private to it.

A package declares what it may reach, and its version:

<!-- manifest: package -->
```toml
[project]
name = "ms-greet"
source = "./src"
version = "1.2.0"
effects = ["std.net.*"]
```

A package holds source only: no `entry`, no `[embed]`, no `extern`, no build scripts. Without `effects` it is pure.

## Workspaces

A workspace splits one repository into projects that share code and one `ms.lock`. The root manifest lists members; a member names another member with a `path` dependency:

<!-- manifest: workspace -->
```toml
[workspace]
members = ["app", "libs/*"]
```

<!-- manifest: member -->
```toml
[project]
name = "app"
source = "src"
entry = "src/main.ms"

[dependencies]
"@util" = { path = "../libs/util" }
```

- Each member is a directory with its own `ms.toml` and a unique `name`; `"libs/*"` means every child with an `ms.toml`. Members stay inside the root; no nested workspaces; cycles are errors.
- `import greet from "@util/greet.ms"` imports a member like a package. A member that uses another member's effects allows them under `[effects]`.
- Run commands from a member, or pass its `ms.toml`. At a root with no `[project]`, `check`, `lint`, `fmt`, `verify` and `test` run on every member; a command that makes one program asks you to name a member.

## Checks

`ms check ms.toml`, then `ms test ms.toml`, then `ms verify`. A missing lock entry says to run `ms install`. Unknown keys, a missing `entry` file, an unknown alias and an unresolved import are errors that name the line.
