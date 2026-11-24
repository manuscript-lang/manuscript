+++
title = "Removed spellings"
weight = 91
+++

# Removed spellings

When Manuscript removes or renames something, the old spelling does not fail quietly. The compiler reports an error that names the new spelling, and `ms check --fix` applies the change when it is mechanical.

| Old | New |
| --- | --- |
| `let x = 1` | `x := 1` |
| `if let v = opt:` | `if v := opt:` |
| `name: Type` in a parameter, field, enum payload, type parameter or binding, such as `fn f(a: Int)` or `x: Int := 1` | `name Type`: `fn f(a Int)`, `x Int := 1`, `[T Comparable]` |
| `fn f(a Int) Int: a` (an inline body after `:`) | `fn f(a Int) Int => a`; a `:` body goes on the next lines |
| `fn x: x + 1`, `fn a, b: a + b`, `fn: 1` | `x => x + 1`, `(a, b) => a + b`, `() => 1`; typed closures keep `fn(a Int) Int => a + 1` |
| `Some(v): v` (an inline arm after `:`) | `Some(v) => v`; a `:` arm's body goes on the next lines |
| `x Int = 1` | `x Int := value`; a typed immutable binding uses `:=` |
| `impl Type:` with methods inside | `fn Type.name(...)`, one per method |
| `fn f(ref x T)` | `fn f(x T)`; a result that is part of a parameter borrows it with no marker. `ref` is an ordinary name, so the old marker reads as a parameter `ref` followed by a stray name |
| `filesystem()` and other host getters | import the operation, such as `read_file` from `@std/os/fs.ms` |
| `@std/concurrency/flow.ms` | `@std/concurrency/resilience.ms` |
| `text.byte_length()` | `text.length()`, which counts bytes |

`ms check --fix` rewrites every row except two, `impl` blocks and host getters, because the new spelling depends on the program. Each row has a test in `tests/checks/removed/`, run by `make removed-check`, which checks both the error and the fix. A change that removes or renames a spelling adds its row and its test.
