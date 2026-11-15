+++
title = "Use a package"
weight = 7
+++

# Use a package

A package is another project's source, fetched by name and version. `ms` pins it, checks it on every build, and never touches the network except when you run `ms install`. This page adds the [Postgres client](https://github.com/manuscript-lang/ms-pg) to a project.

## Add the package

```sh
ms add https://github.com/manuscript-lang/ms-pg.git --sha <40-character commit> --allow
```

`ms add` writes the dependency into `ms.toml`, downloads it with `git`, records the commit and a content hash in `ms.lock`, and prints what the package may reach. The name defaults to the repository name without a leading `ms-`, so this is `@pg`; `--as @name` picks another. Pass `--tag v1.0.0` instead of `--sha` when the repository has a tag you trust.

The result in `ms.toml` is a table with the git `url` and a `tag` or a full `sha`:

```toml
[dependencies]
"@pg" = { url = "https://github.com/manuscript-lang/ms-pg.git", sha = "<40-character commit>" }

[effects]
"@pg" = ["std.net.*", "std.clock.read", "std.random.read"]
```

`[effects]` is what you allow the package to reach, a list of effect patterns. The package declares its own list; if it asks for more than you allow, `ms` rejects it and names the extra effect. `--allow` writes the package's declaration there; without it, `ms add` prints the line to add. A package that adds an effect in a later version fails your build until you edit this line.

Commit `ms.lock`. Everyone who builds the project gets the same bytes: a changed file, or a tag that moved, is an error. Nothing runs when a package is fetched, and every command except `ms add`, `ms install` and `ms remove` works offline from the cache.

`ms install` downloads everything `ms.toml` names, exactly as `ms.lock` pins it. Run it after cloning a project or after editing `[dependencies]` by hand.

## Import it

`@pg/` names the package's source directory:

```manuscript
import Config, open from "@pg/conn.ms"
import Value from "@pg/value.ms"

fn main() Void!:
    var conn = open(Config(password: "secret"))?
    rows := conn.query("select $1::int8 + 1", [Value.Int(41)])?
    print("{rows.rows[0][0]}")
    conn.close()?
    return ok(unit)
```

Go to definition on `open` opens the package's file in the cache. The file is read-only.

## Update or remove a package

```sh
ms install --update @pg
ms remove @pg
```

`--update` resolves one dependency again and rewrites its lock line. To move to a new commit, edit the value in `ms.toml` and run `ms install`. `ms remove` takes the dependency out of `ms.toml` and `ms.lock`; the cached copy stays in the package cache.

Two versions of one repository can sit in a project under two names. Their types are different, and the checker says so when they meet: it names both paths and both tags.

## Rules in short

- A package is a library: an `ms.toml` with `source` and no `entry`, and Manuscript source only. No `extern`, no build scripts.
- A package's own dependencies are private to it.
- Dependencies use `https://`. `ms.lock` is checked as untrusted input.

The full rules, including the cache location and the hash, are in [project configuration](../developer-tooling/builds/project-configuration.md#packages).
