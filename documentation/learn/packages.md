+++
title = "Use a package"
weight = 4
+++

# Use a package

A package is another project's source, fetched by name and version. `ms` pins it, checks it on every build, and never touches the network except when you run `ms fetch`. This page adds the [Postgres client](https://github.com/manuscript-lang/ms-pg) to a project.

## Name the package

Add it to `ms.toml`. The value is a git URL, `#`, and a tag or a full commit. Pin a full commit when the repository has no tag you trust.

```toml
[project]
name = "visits"
source = "src"
entry = "src/main.ms"

[dependencies]
"@pg" = "https://github.com/manuscript-lang/ms-pg.git#<40-character commit>"

[effects]
"@pg" = ["std.net.*", "std.clock.read", "std.random.read"]
```

`[effects]` is what you allow the package to reach, a list of effect patterns. The package declares its own list; if it asks for more than you allow, `ms` rejects it and names the extra effect. A package that adds an effect in a later version fails your build until you edit this line.

## Fetch and lock

```sh
ms fetch
```

`ms fetch` downloads the package with `git`, records the commit and a content hash in `ms.lock`, and prints what the package may reach. Commit `ms.lock`. Everyone who builds the project gets the same bytes: a changed file, or a tag that moved, is an error.

Nothing runs when a package is fetched. Every other command works offline from the cache.

## Import it

`@pg/` names the package's source directory:

```manuscript
import Config, open from "@pg/conn.ms"
import Value from "@pg/value.ms"

fn main() Unit!:
    var conn = open(Config(password: "secret"))?
    rows := conn.query("select $1::int8 + 1", [Value.Int(41)])?
    print("{rows.rows[0][0]}")
    conn.close()?
    return ok(unit)
```

Go to definition on `open` opens the package's file in the cache. The file is read-only.

## Update or pin another version

```sh
ms fetch --update @pg
```

re-resolves one dependency and rewrites its lock line. To move to a new commit, edit the value in `ms.toml` and run `ms fetch`.

Two versions of one repository can sit in a project under two names. Their types are different, and the checker says so when they meet: it names both paths and both tags.

## Rules in short

- A package is a library: an `ms.toml` with `source` and no `entry`, and Manuscript source only. No `extern`, no build scripts.
- A package's own dependencies are private to it.
- Dependencies use `https://`. `ms.lock` is checked as untrusted input.

The full rules, including the cache location and the hash, are in [project configuration](../developer-tooling/builds/project-configuration.md#packages).
