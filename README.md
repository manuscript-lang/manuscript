# Manuscript

**A small, statically typed language that compiles to fast native executables, built so agents and people get it right the first time.**

[Why Manuscript](documentation/learn/why-manuscript.md) · [Take the tour](documentation/learn/tour.md) · [Read the book](https://manuscript-lang.github.io/manuscript/) · [Download](https://github.com/manuscript-lang/manuscript/releases)

- **Fast.** Native code through LLVM: ahead of hand-written Go on 26 of 31 benchmarks, and typically within 1.4x of Rust with overflow checks on.
- **No garbage collector.** Memory is deterministic: every value has one owner and is dropped at a known point, so there are no collection pauses and no tracing runtime.
- **One binary.** `ms` is the compiler, formatter, linter, test runner, language server, and profiler. No C toolchain, SDK, or package manager to install. An HTTP server is about 4.4 MB.
- **Agents succeed with it.** Claude Haiku 5.5 passes 9 of 10 small challenges and 8 of 10 large applications (3-5k lines) on the [agent bench](bench/agent/results/summary-2026-10-21.md), with compact source.
- **Little to get wrong.** Pipes, inferred ownership and borrowing, failure as a value, and no implicit conversion or truthiness.

## A taste

Typed JSON, optional values, error propagation with `try`, and a test, in one file:

```manuscript
import {parse, stringify} from "@std/json.ms"
import expect_equal from "@std/testing.ms"

type Order:
    customer: String
    cents: Int
    coupon: Optional[String]

fn discount(order: Order) Int:
    if let code = order.coupon:
        return if code == "SAVE10": order.cents / 10 else: 0

    return 0

fn summary(text: String) Result[String, Error]:
    let orders = try parse[List[Order]](text)
    var total = 0
    for order in orders:
        total += order.cents - discount(order)
    return ok("{orders.length()} orders, {total / 100} dollars")

test "orders from JSON":
    let sam = Order(customer: "Sam", cents: 5000, coupon: some("SAVE10"))
    let ana = Order(customer: "Ana", cents: 2500, coupon: none)
    let text = try stringify([sam, ana])
    try expect_equal(try summary(text), "2 orders, 70 dollars")
    try expect_equal(summary("not json").is_error(), true)
```

Run it with `ms test`. `parse[List[Order]]` reads text straight into your types and returns a `Result`; `try` hands any error to the caller; `Optional` fields unwrap with `if let`. There are no exceptions to forget about.

## What makes it different

**Pipes instead of nesting.** A `|` flow feeds each result into the next call, so a chain of steps reads top to bottom. A `try` step unwraps a `Result` or returns its error (`x | try parse | .total()`), so there are no nested calls and no `Result` matching:

```manuscript
import expect_equal from "@std/testing.ms"

type Reading:
    sensor: String
    celsius: Float

fn hot(readings: List[Reading]) List[Reading]:
    return readings.filter(
        fn(reading: Reading) Bool:
            return reading.celsius > 30.0
    )

fn names(readings: List[Reading]) String:
    return readings.map(
        fn(reading: Reading) String:
            return reading.sensor
    ).join(", ")

fn alert(readings: List[Reading]) String:
    return readings | hot | names

test "pipe flow":
    let readings = [
        Reading(sensor: "a", celsius: 21.5),
        Reading(sensor: "b", celsius: 35.0)
    ]
    try expect_equal(alert(readings), "b")
```

**Ownership and borrow checking with no extra syntax.** Every value has one owner and is dropped at a known point: no garbage collector, no pauses, no lifetime annotations, and the checker infers whether each parameter only reads, mutates, or consumes its argument. The one marker you write is `var`, on the parameter and again at the call, exactly where a function changes its argument:

```manuscript
type Cart:
    items: List[String]

fn add(var cart: Cart, item: String) Unit:
    cart.items.append(item)

fn count(cart: Cart) Int:
    return cart.items.length()

fn pay(cart: Cart) Cart:
    return cart

fn demo() Int:
    var cart = Cart(items: [])
    add(var cart, "book")
    let seen = count(cart)
    let receipt = pay(cart)
    return seen + receipt.items.length()
```

Passing `cart` to `count` is a borrow; passing it to `pay`, which returns it, is a move at its last use. Use `cart` again after the move and the checker rejects the program with a fix an agent can apply:

```text
`cart` is moved here but used again at 18:25; a value has one owner, so pass `cart.clone()` to keep the original, or move it only at its last use
```

The ownership check runs on every program, so a whole class of aliasing bugs never reaches a test. Cleanup is just as direct: `with file = try files.open("data.txt"):` closes the resource at block end, on errors too.

**Failure is a value.** `Optional` and `Result` make absence and errors part of the type, and `try` propagates them. I/O is an ordinary call, with no async syntax.

**Everything is one tool.** The same `ms` binary that compiles your program also formats, lints, tests, profiles, and answers an agent's questions with `--json`. See [Built for the agent loop](#built-for-the-agent-loop).

## Fast without ceremony

Ordinary code, compiled natively (linux/amd64, Manuscript time as a fraction of hand-written Go's; lower is faster):

| Program | Manuscript vs Go |
| --- | ---: |
| Game of Life, 128x128 for 50 generations | 0.06x |
| Stack of 20M pushes and pops | 0.14x |
| Sorting 1M items with a comparator | 0.26x |
| Parsing and splitting 1M lines of text | 0.45x |
| Calling a captured closure 100M times | 0.50x |
| `Result` propagation with `try`, 50M calls | 0.56x |

Across all 31 benchmarks it is faster than Go on 26, and typically within 1.4x of Rust with overflow checks on (sorting with a comparator is within 1.2x). Linux and macOS release builds optimize with LLVM through tools bundled in `ms`. Unreached runtime and standard-library code is dropped at link time: an empty program is about 0.45 MB. Methods and numbers: [programs](bench/perf/programs/results.md), [competence](bench/perf/competence/README.md), [kernels](bench/perf/kernels/README.md).

## Built for the agent loop

Manuscript shapes the language and the toolchain together around the loop an agent runs: write, check, fix, verify, ship.

- **Evidence, not prose.** `--json` from `check`, `lint`, `test`, `build`, and `inspect`; `ms search_symbol` finds exact APIs, `ms guide` prints the cheat sheet, `ms verify` runs check, format, lint, and test in one result, and `ms review` and `ms diagram` show the effect of a change from the checked source.
- **Flat, regular code.** Four-space blocks, `|` pipe flows, `try`, exhaustive `match`, and `with` for scoped cleanup. Values have one owner: moves happen at last use, `var` marks mutation at the declaration and the call, and `.clone()` copies explicitly.
- **Measured on real agents.** [`agent-bench`](bench/agent/README.md) runs real challenges with real agents. Failures there drive diagnostics, docs, and the cheat sheet.
- **A batteries-included standard library.** Files, processes, networking, HTTP, JSON, text, and time, plus `Queue`, `Deque`, `BitSet`, `SortedMap`, and `SortedSet`.

See the [tooling guide](documentation/developer-tooling/implementation.md), [how it works](documentation/developer-tooling/how-it-works.md), and [VS Code integration](extensions/vscode/README.md). For direction, read the [vision](VISION.md).

## Try it

Extract the [release archive](https://github.com/manuscript-lang/manuscript/releases). It includes `ms` and the hello project; nothing else to install.

From the extracted directory, run:

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

On Windows PowerShell, use `.\ms.exe`.

```text
Arguments: 2
```

`check` validates source; `run` builds a temporary executable and passes it arguments after `--`.

Start a project with `./ms init my-app`, or keep an executable and run the test:

```sh
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

`./ms --help` lists commands; `fmt` formats and `lint` reports findings. See [your first program](documentation/learn/getting-started.md).

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn the language | [Language tour](documentation/learn/tour.md) and [core language](documentation/core-language/_index.md) |
| Find a standard type or function | `ms search_symbol <name or words>` and the [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) |
| Understand cleanup | [Resource lifetimes](documentation/core-language/cleanup/_index.md) and [runtime conventions](documentation/contributing/runtime-conventions.md) |
| Set up your editor or use source tools | [VS Code extension](extensions/vscode/README.md) and [tooling guide](documentation/developer-tooling/implementation.md) |
| Understand what `ms` bundles | [How it works](documentation/developer-tooling/how-it-works.md) |
| Choose optimization and debugging settings | [Build levels](documentation/developer-tooling/builds/build-levels.md) |

## Project status

Version 0.1: working compiler, runtime, standard library, test runner, formatter, and editor tooling, still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work.

## Build from source

Releases ship the Rust `ms`. To build it from a checkout, install [rustup](https://rustup.rs) and a C compiler (`cc`; `clang` on Windows; the `ring` crate compiles C sources while building the runtime), then:

```sh
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

See the [Rust toolchain guide](documentation/contributing/rust-toolchain.md) for checks, crates, and platform behavior.

## Contribute

See the [architecture guide](documentation/contributing/architecture.md), [development and publishing](documentation/contributing/development.md), and [maintenance](documentation/contributing/maintenance.md). Routine checks: `make setup`, `make doctor`, `make verify`; `make verify-full` adds the conformance corpus, book, and distribution checks. Rust changes also run `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo nextest run --workspace`.

Layout: `crates/` (compiler, runtime, tooling), `documentation/` (guides), [stdlib/](stdlib/intrinsics.ms) (standard declarations). The website builds into ignored `.artifacts/book/`.
