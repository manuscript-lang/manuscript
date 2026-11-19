# Projects, ms.toml and packages

`ms init <name>` (or `--lib`) creates `ms.toml`, `src/main.ms`, `test.ms`. Run `ms check|run|test|build ms.toml`. TOML strings are quoted; keys starting with `@` are quoted.

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

- Only `[project]`, `[workspace]`, `[aliases]`, `[embed]`, `[dependencies]`, `[effects]` exist; unknown or duplicate keys are errors. Paths are relative to `ms.toml`; `entry` is not relative to `source`. Omit `entry` for a library. `version = "1.2.3"` is for packages.
- Modules are found by following imports from the entry. `ms check ms.toml` checks every `.ms` below `source` plus `test.ms` and `*_test.ms`.

## Imports
`./x.ms` and `../x.ms` are relative; `@std/data/json.ms` is the standard library; `@domain/orders.ms` is a directory alias plus path; `@customers` is a file alias. Always write `.ms`; only `export`ed names import (`import Order, total from "@domain/orders.ms"`). No wildcards, cycles or absolute paths.

`[embed]` bakes a directory in (`"@assets" = "./assets"`): `import files from "@assets"`, then `files().read("message.txt", none)` (`@std/os/tree.ms`). Write the name alone; it cannot also be an alias.

<!-- manifest: embed -->
```toml
[project]
name = "site"
source = "./src"
entry = "./src/main.ms"

[embed]
"@assets" = "./assets"
```

## Packages
`ms add <git url> --version 1.2 --allow` (or `--tag`, `--sha <40 hex>`) edits `ms.toml` and `ms.lock` (commit it); `--allow` also writes the effects the package declares. `ms remove @name`, `ms install` (restores everything), `ms install --update @name`. Only these use the network.

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

- A dependency has `url` plus exactly one of `version` (`1.2`, `^1.2`, `~1.2.3`, `=1.2.3`; no ranges), `tag` or `sha`.
- `[effects]` lists what you allow each dependency; a package declaring more is rejected. Import like an alias: `import Config, open from "@pg/conn.ms"` (path under the package's `source`). A package's own dependencies are private.
- A package holds source only (no `entry`, `[embed]`, `extern` or build scripts) and declares `effects` and `version`; without `effects` it is pure.

<!-- manifest: package -->
```toml
[project]
name = "ms-greet"
source = "./src"
version = "1.2.0"
effects = ["std.net.*"]
```

## Workspaces
`[workspace] members = ["app", "libs/*"]` at the root; each member has its own `ms.toml` and unique `name`; members name each other with `path` dependencies (`"@util" = { path = "../libs/util" }`) and import `@util/greet.ms`. Members stay inside the root; no nesting or cycles. At a root with no `[project]`, `check`, `lint`, `fmt`, `verify` and `test` run on every member; commands that make one program need a member.

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

```manuscript
import Order, total from "@domain/orders.ms"
import Config, open from "@pg/conn.ms"
```
