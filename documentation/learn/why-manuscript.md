+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

**The language for the agentic era.**

Soon most code will be written by agents. You will still own it. You won't read every line, but you will need to understand what a program does, what can fail, and who owns what, and you will need to trust it enough to ship it.

Manuscript is a language and a toolchain designed for that arrangement. Here is what it looks like to build something with an agent.

## A language that is simple to read and cheap to write

A model writes Manuscript well because there is little to get wrong. The concepts are the ones you already know: functions, types, interfaces, enums and generics. Types are simple (`Int`, `String`, `List[T]`, `Map[K, V]`), generics read as they look (`fn sum_by[T](...)`), and most code is easy to follow top to bottom. Here is a small program an agent might write for a shop.

<!-- manuscript-example: {"mode":"run","stdout":"1650 cents\n"} -->
```manuscript {filename="shop.ms"}
import stdout from "@std/io/io.ms"

enum Item:
    Book(pages: Int)
    Coffee(grams: Int)

interface Priced:
    fn cents() Int

impl Priced for Item:
    fn cents() Int:
        match self:
            Book(pages): return 500 + pages * 2
            Coffee(grams): return grams * 3

fn sum_by[T](items: List[T], price: fn(T) Int) Int:
    var total = 0
    for item in items:
        total += price(item)
    return total

export fn main() Int:
    let cart = [Item.Book(pages: 200), Item.Coffee(grams: 250)]
    let total = sum_by(cart, fn item: item.cents())
    stdout().write("{total} cents\n").get()
    return 0
```

```text
1650 cents
```

You can follow this without a manual. An `enum` lists the cases, an `interface` names what a type can do, `impl` connects them, and `match` covers every case. `var` marks the one thing that changes. Nothing is copied behind your back, because the only mark for that is `.clone()`. Each value has one owner, the compiler frees it at its last use, and there is no garbage collector and no lifetime annotation.

The syntax is also cheap for a model to produce. Manuscript spells logic with plain English words, `and`, `or`, `not`, `fn`, `var`, `else if`, `none`, where other languages use symbols and punctuation. Plain words are common in a model's training text and tend to cost fewer tokens than strings of operators, so the same program takes less to write and less to read back.

## A compiler that helps the agent

Agents carry habits from other languages. They write `len(xs)`, `&&`, `null`, `xs.push(1)` or `i++`. The compiler is built to meet them there. Every diagnostic reads `cause; fix`, and it recognizes code that looks like it came from somewhere else:

```text
resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
parse: '&&' is not an operator; write 'and' for logical and
resolution: unknown binding null; Manuscript has no null: absence is an Optional, written none
resolution: unknown or ambiguous member push on List[Int]; did you mean 'append'?
```

The agent gets the repair, not just "syntax error". When the fix is mechanical, `ms check --fix` applies it: `null` becomes `none` and `push` becomes `append` without another round trip. An ownership slip is explained the same way, with the `.clone()` that keeps the original.

Checking is fast, so the agent can ask after every edit: on a 122,000-line project, `ms check` takes under two seconds (see the numbers below). `ms guide` is a one-page cheat sheet, `ms search_symbol read file` answers one API question, and `ms verify` runs checks, formatting, lint and tests with a single exit code. When a program fails at run time, `ms test --json` hands back the fault as data: kind, values, position and trace. The agent loops until the exit code is zero.

## Easy to review and understand

Reading the diff line by line does not scale when an agent writes the code. Manuscript is simple enough that the code is easy to follow, and the tooling shows what a program does before you read any of it. You run:

```sh
ms diagram ms.toml --format html -o code-map.html
```

You get one offline file that shows source, types, calls and ownership side by side, with the declarations the change touched highlighted: `Changed (3)` in the sidebar below lists them, and the Behavior view lays out the control flow of the selected function. The actual code is one click away from any box in the picture. `ms review --diff` ranks what deserves your attention first: changed contracts, error flow and resource scopes. A file or connection opened in a scope closes when the scope exits, even on an early return, a fault or a cancellation, so there is less to check by eye. The language and the tools are shaped to keep the cognitive load low: you see the structure first and open the code only where it matters.

![The code map for an inventory tool, with three changed declarations listed in the sidebar and the Behavior view of run_command beside its source](/images/code-map-behavior.png "Code map with a diff overlay: changed declarations are outlined in red, and the Behavior view shows each branch and early return.")

## Test, benchmark and profile in one toolchain

Agents are good at improving what they can measure. Manuscript puts the measuring tools in the same package as the compiler, so an agent can write code, prove it works and make it faster without leaving the toolchain.

- **Test.** `test` blocks sit beside the code and run with `ms test`. Property tests draw inputs nobody thought of and shrink any failure to a small case, and `ms test --fuzz 30s` turns the same tests into a fuzzer.
- **Benchmark.** `bench` blocks run under `ms bench`, which times each one over repeated samples, so a change is a number, not a feeling.
- **Profile.** `ms profile` samples a running program and reports where the time goes, so the agent optimizes the hotspot instead of guessing.

The loop is the one a person would follow: measure, change one thing, measure again. The toolchain is designed for an agent to run that loop on its own.

## Hardened with frontier models

Manuscript is young, and the project is hardened with frontier models. We use them to find edge cases, bugs, memory leaks and performance regressions, and to fix them.

The method is simple. For correctness, a model probes one area at a time: it writes programs against new features and their edges, compares what happens with the documented rule, and fixes real bugs with regression tests. For performance, it starts from a measured gap, reproduces it, changes one thing, and shows before and after on the same machine. A fix that costs more than it earns is dropped.

## Fast to iterate, fast to ship

The compiler is a pipeline that gets slower and smarter at each step:

```text
Manuscript source -> HIR -> MIR -> CLIF -> LLVM
```

The early stages are far cheaper than the late ones, so you stop as early as the task allows. Check while you write, run a quick debug build to try it, and pay for LLVM only when you ship. As a program matures you can spend more of the pipeline on it, and the optimizations that earn their cost are the ones you keep. An agent that runs the compiler dozens of times per task lives in the cheap stages; the binary you deploy comes out of the expensive ones.

On a generated 122,000-line project (40 packages, cold build, 4 vCPUs), the same program in three languages:

| step | Manuscript | Go | Rust |
|---|---:|---:|---:|
| check only | 1.6 s | 11.6 s (`go vet`) | 16.8 s (`cargo check`) |
| debug build | 4.8 s | 10.5 s (`go build`) | 18.0 s (`cargo build`) |
| release build | 43.8 s (LLVM) | 10.5 s | 30.5 s (`cargo build --release`) |

The numbers come from the [compile-time benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/compile-time/README.md), which generates the same program in each language and names the machine and command. The Rust version is one crate with 40 modules, the closest match for Go's 40 packages.

## We measure it with agents

The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) gives agents the same challenges in TypeScript, Go, Rust and Manuscript and grades them on hidden tests. What goes wrong there decides what we build next. Every result types its revision and machine.

## Where it stands

The language core, the `ms` toolchain and the standard library work today. Syntax and APIs still evolve, and each release hardens them further. The [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) describes where this is heading.

**Next:** [Run your first program](getting-started.md)
