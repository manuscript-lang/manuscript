# Manuscript

Manuscript is the language for the agentic era.

Agents write the code and people understand it. It is statically typed, compiles to fast, self-contained native executables, and keeps its core small and regular, so an agent can write a confident first draft and a person can read, inspect, and verify the result.

[Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [The book](https://manuscript-lang.github.io/manuscript/) · [Download](https://github.com/manuscript-lang/manuscript/releases)

## Highlights

- **Clear syntax, no tricks.** Familiar names, four-space blocks, and one obvious spelling instead of clever alternatives. An agent can write it reliably and a person can read it at a glance. Claude Haiku 5.5 passes 9 of 10 small challenges and 8 of 10 large applications (3-5k lines) on the [agent bench](bench/agent/results/summary-2026-10-21.md).
- **Simple, fast memory.** Value semantics with move and copy, no garbage collector, deterministic cleanup. Nothing is copied unless you write `.clone()`, and the only ownership marker is `var`.
- **Fast, and closing in on Rust.** Native code through LLVM: faster than hand-written Go on 26 of 31 benchmarks, and within 1.25x of Rust (overflow checks on) on most kernels, ahead on several.
- **One binary.** `ms` is the compiler, formatter, linter, test runner, language server, and profiler. It needs no C toolchain or SDK.

## Example

Typed JSON, optional values, error propagation with `try`, and a test in one file:

```manuscript
from "@std/json.ms" import parse, stringify
from "@std/testing.ms" import expect_equal

type Order:
    customer: String
    cents: Int
    coupon: Optional[String]

def discount(order: Order) -> Int:
    if let code = order.coupon:
        return order.cents / 10 if code == "SAVE10" else 0
    else:
        return 0

def summary(text: String) -> Result[String, Error]:
    let orders = try parse[List[Order]](text)
    var total = 0
    for order in orders:
        total += order.cents - discount(order)
    return ok(f"{orders.length()} orders, {total / 100} dollars")

test "orders from JSON":
    let sam = Order(customer: "Sam", cents: 5000, coupon: some("SAVE10"))
    let ana = Order(customer: "Ana", cents: 2500, coupon: none)
    let text = try stringify([sam, ana])
    try expect_equal(try summary(text), "2 orders, 70 dollars")
    try expect_equal(summary("not json").is_error(), True)
```

Run it with `ms test`. `parse[List[Order]]` reads text into your types and returns a `Result`, `try` passes any error to the caller, and `Optional` fields unwrap with `if let`.

## The language

### Pipes

A `|` flow passes each result to the next call, so a sequence of steps reads from top to bottom. A `try` step unwraps a `Result` or returns its error.

```manuscript
from "@std/testing.ms" import expect_equal

type Reading:
    sensor: String
    celsius: Float

def hot(readings: List[Reading]) -> List[Reading]:
    return readings.filter(
        lambda (reading: Reading) -> Bool:
            return reading.celsius > 30.0
    )

def names(readings: List[Reading]) -> String:
    return readings.map(
        lambda (reading: Reading) -> String:
            return reading.sensor
    ).join(", ")

def alert(readings: List[Reading]) -> String:
    return readings | hot | names

test "pipe flow":
    let readings = [
        Reading(sensor: "a", celsius: 21.5),
        Reading(sensor: "b", celsius: 35.0)
    ]
    try expect_equal(alert(readings), "b")
```

### Value semantics and ownership

Records, lists, maps, and sets are values, so two names never change one object. Small values copy implicitly; everything else moves at its last use, which passes data along without copying it. `.clone()` is the only deep copy and is always visible. Every value has one owner and is dropped at a known point, so there is no garbage collector and no pause.

The compiler checks this on every program, with no lifetime annotations. It infers whether each parameter reads, mutates, or consumes its argument. The one marker you write is `var`, on the parameter and again at the call, exactly where a function changes its argument:

```manuscript
type Cart:
    items: List[String]

def add(var cart: Cart, item: String) -> Unit:
    cart.items.append(item)

def count(cart: Cart) -> Int:
    return cart.items.length()

def pay(cart: Cart) -> Cart:
    return cart

def demo() -> Int:
    var cart = Cart(items: [])
    add(var cart, "book")
    let seen = count(cart)
    let receipt = pay(cart)
    return seen + receipt.items.length()
```

`count` borrows `cart`. `pay` consumes it, so the move happens at its last use. Using `cart` after that is rejected, with a fix the compiler states:

```text
`cart` is moved here but used again at 18:25; a value has one owner, so pass `cart.clone()` to keep the original, or move it only at its last use
```

Cleanup follows the same ownership. `with let file = try files.open("data.txt"):` closes the resource at the end of the block, including when an error occurs.

### Errors

`Optional` and `Result` put absence and failure in the type, and `try` propagates them. Input and output are ordinary calls, so no function needs special async syntax.

## Performance

Representative programs compiled natively (linux/amd64), as a fraction of hand-written Go's time; lower is faster.

| Program | Manuscript / Go |
| --- | ---: |
| Game of Life, 128x128 for 50 generations | 0.09 |
| Stack of 20M pushes and pops | 0.11 |
| Sorting 1M items with a comparator | 0.14 |
| Parsing and splitting 1M lines of text | 0.45 |
| `Result` propagation with `try`, 50M calls | 0.57 |
| `Optional` construction and `if let`, 100M | 0.66 |

Across all 31 benchmarks Manuscript beats Go on 26. Against Rust with overflow checks on, most kernels are within 1.25x and several are ahead (dispatch, sort, string-keyed maps, grids, optionals, sets). Whole programs are level or ahead on sieve, matmul, trees, collatz, and map counting, and within 1.3x on n-body and life. Unreached runtime and standard-library code is removed at link time, so an empty program is about 0.45 MB. Methods and numbers: [programs](bench/perf/programs/results.md), [competence](bench/perf/competence/README.md), [kernels](bench/perf/kernels/README.md).

## Built on measurement

Language and compiler choices are settled by benchmarks, not taste.

- **Agents.** [`agent-bench`](bench/agent/README.md) gives real agents the same challenges in TypeScript, Go, Rust, and Manuscript, and checks their output against hidden tests. Failures drive changes to diagnostics, documentation, and the `ms guide` cheat sheet.
- **Speed.** [`bench/perf`](bench/perf/README.md) times Manuscript against hand-written Go and Rust. A design that cannot show a measured gain does not get built.

## Tools for the loop

An agent writes, checks, fixes, and verifies; a person guides and inspects. `check`, `lint`, `test`, `build`, and `inspect` accept `--json`; `ms verify` runs check, format, lint, and test in one result; `ms search_symbol` finds exact APIs. Compiler messages name the next step. The standard library covers files, processes, networking, HTTP, JSON, text, and time.

See the [tooling guide](documentation/developer-tooling/implementation.md), [how it works](documentation/developer-tooling/how-it-works.md), and [VS Code integration](extensions/vscode/README.md). The [vision](VISION.md) describes where the project is heading.

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
