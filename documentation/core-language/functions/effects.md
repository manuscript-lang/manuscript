+++
title = "Effects and permissions"
weight = 4
+++

# Effects and permissions

A function is pure unless a comment permits what it reaches. `ms lint` reports a function that prints, reads a file, calls the network or reads the clock without that permission, and names the call that brings the effect in. Effects are comments, so the language has no extra syntax.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn total(prices: List[Int]) Int:
    print("summing {prices.length()} prices")
    sum := prices.sum()
    return sum

export fn main() Int:
    print(total([2, 3]))
    return 0
```

```text
a.ms:2:5: warning MSL116: `total` reaches std.console.write: total -> print; permit it with `// ms: allow_effect std.console.write`, move the call to the caller, or take a capability parameter
```

`main`, `test` and `fixture` may do anything, so `main` is not reported. `total` is: the `print` is a surprise in a function that only adds numbers.

## Permit what a function needs

`// ms: allow_effect NAME` directly above a function permits it to reach that effect. Put the lines at the top of a file, ended by a blank line, to cover every function in the file. A function's own lines can only narrow its file's.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
// ms: allow_effect std.fs.read

import read_file from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn load(path: String) Bytes!:
    return read_file(path).wait()

export fn main() Int:
    return 0
```

Each line names one effect or a pattern:

| Line | Permits |
| --- | --- |
| `std.fs.read` | that effect only |
| `std.fs.*` | every effect under `std.fs` |
| `*.read` | every effect that ends in `read` |
| `*` | everything |

A file with no line is pure. Prefer the narrowest line, and prefer passing a capability over a wide permission.

## Pass a capability instead

A function that is handed an interface value does not need a permission to use it. The permission belongs where the value is made.

<!-- manuscript-example: {"mode":"run","stdout":"> summing 2 prices\n5\n"} -->
```manuscript
interface Logger:
    fn info(message: String) Unit

type ConsoleLogger:
    prefix: String

impl Logger for ConsoleLogger:
    // ms: allow_effect std.console.write
    fn info(message: String) Unit:
        print("{self.prefix}{message}")

fn total(log: Logger, prices: List[Int]) Int:
    log.info("summing {prices.length()} prices")
    sum := prices.sum()
    return sum

export fn main() Int:
    print(total(ConsoleLogger("> "), [2, 3]))
    return 0
```

`total` is pure here, so a test can pass a logger that records messages. Turning a `ConsoleLogger` into a `Logger` inside a pure function would be reported, because that is where the authority is obtained. The same holds when a function is written as a closure, named as a value, or passed for a generic parameter.

## Declare your own effect

`// ms: effect NAME` says a function performs `NAME`. Callers see that name instead of what the body reaches, so a wrapper can hide how it works.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import write_file from "@std/os/fs.ms"

// ms: effect db.write
// ms: allow_effect std.fs.write
fn save(order: String) Unit!:
    return write_file("orders.log", order).wait()

// ms: allow_effect db.*
fn checkout(total: Int) Unit!:
    return save("order {total}")

fn audit(total: Int) Unit!:
    return save("audit {total}")

export fn main() Int:
    return 0
```

`save` may write a file and declares `db.write`. `checkout` may use any `db` effect but not the file system directly. `audit` has no line, so it is reported for `db.write`. Names starting with `std.` belong to the standard library.

## Standard-library effects

Standard-library functions declare what they let a caller do. Calls through a handle you already hold, such as reading from an open file, do not need a second permission.

| Effect | Covers |
| --- | --- |
| `std.fs.read`, `std.fs.write`, `std.fs.delete` | files and directories |
| `std.net.connect`, `std.net.listen` | network clients and servers |
| `std.process.run`, `std.process.signal`, `std.process.read`, `std.process.write` | starting, signalling and inspecting processes |
| `std.env.read`, `std.env.write` | environment variables and the working directory |
| `std.clock.read`, `std.clock.sleep` | the current time and waiting |
| `std.random.read` | random values |
| `std.console.read`, `std.console.write` | standard input, output and error |
| `std.system.read` | host facts such as the hostname and system roots |

`ms search_symbol read_file` prints `effects: std.fs.read`, and hovering a function in the editor shows its effects, its permissions, or that it is pure.

## Seeing and reviewing effects

- `ms lint` reports `MSL116` as a warning for now; `--deny-warnings` makes it fail. It becomes an error in a later release.
- `ms review ms.toml --diff change.patch` lists new permissions and newly reached effects under `EFFECT+`, permissions first. `--effect 'std.net.*'` keeps only the findings for one effect.
- [Understanding effects](../../developer-tooling/source/effects.md) describes the separate call-graph view.

## Limits

- Pure means no ambient authority, not no input or output at run time: a pure function can use a handle it was given.
- Effects are not tracked through values or checked while the program runs. Generic calls charge the interface methods of the concrete type argument.
- Code outside the language, such as a native library declared with `extern fn`, is not covered.
