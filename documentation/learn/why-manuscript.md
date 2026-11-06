+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

**The language for the agentic era.**

Soon most code will be written by agents. You will still own it. You won't read every line, but you will need to understand what a program does, what can fail, and who owns what, and you will need to trust it enough to ship it.

Manuscript is a language and a toolchain designed for that arrangement. Here is what it looks like to build something with an agent.

## The agent writes a program

You ask for a small tool that totals orders by customer from a JSON file. The agent writes this.

<!-- manuscript-example: {"mode":"run","files":{"orders.json":"[{\"customer\":\"Sam\",\"cents\":1250},{\"customer\":\"Ada\",\"cents\":4000},{\"customer\":\"Sam\",\"cents\":3100}]"},"stdout":"Sam: 4350 cents\nAda: 4000 cents\n"} -->
```manuscript {filename="totals.ms"}
import read_file from "@std/os/fs.ms"
import parse from "@std/data/json.ms"

type Order:
    customer: String
    cents: Int

fn totals(path: String) Map[String, Int]!:
    let text = try read_file(path).wait()
    let orders = try parse[List[Order]](try text.decode_utf8().ok_or())
    var sums = Map[String, Int]()
    for order in orders:
        let total = sums.get(order.customer).get(0) + order.cents
        sums.add(order.customer, total)
    return ok(sums)

export fn main() Int:
    let sums = totals("orders.json")
    if sums.is_error():
        print(sums.err().message)
        return 1
    for entry in sums.get().entries():
        print("{entry.key}: {entry.value} cents")
    return 0
```

```text
Sam: 4350 cents
Ada: 4000 cents
```

You can understand this without reading every line. `totals` can fail, because of the `!`, and each `try` marks a place it can. If `orders.json` is missing or malformed, the caller gets an error message instead of a crash:

```text
filesystem: file or directory not found: orders.json
```

`var sums` is the only thing that changes. Nothing is copied behind your back, because the only mark for that is `.clone()`. Each value has one owner, the compiler frees it at its last use, and there is no garbage collector and no lifetime annotation. Those few marks are how you understand a change without reading all of it.

## The agent makes a mistake

Agents carry habits from other languages. This one first tried to add the total in one line, using `order.customer` as the key and again for the lookup:

```manuscript
        sums.add(order.customer, sums.get(order.customer).get(0) + order.cents)
```

The compiler stops it and says how to repair it:

```text
totals.ms:13:24: type: `order.customer` is moved here but used again at 13:43; a value has one owner, so use `order.customer.clone()` to keep the original, or move it only at its last use
```

Every diagnostic reads `cause; fix`. When an agent writes `len(xs)`, the answer is not "syntax error" but `there is no len() function: call the length member, e.g. xs.length()`. When the fix is mechanical, `ms check --fix` applies it. When a program fails at run time, `ms test --json` hands back the fault as data: kind, values, position and trace. The agent never needs the whole manual. `ms guide` is a one-page cheat sheet, `ms search_symbol read file` answers one API question, and `ms verify` runs checks, formatting, lint and tests with a single exit code. The agent loops until that exit code is zero.

## You review the result

You don't read the diff top to bottom. You run:

```sh
ms diagram ms.toml --format html -o code-map.html
```

You get one offline file that shows source, types, calls and ownership side by side, with the declarations the change touched highlighted: `Changed (3)` in the sidebar below lists them, and the Behavior view lays out the control flow of the selected function. `ms review --diff` ranks what deserves your attention first: changed contracts, error flow and resource scopes. A file or connection opened in a scope closes when the scope exits, even on an early return, a fault or a cancellation, so there is less to check by eye.

![The code map for an inventory tool, with three changed declarations listed in the sidebar and the Behavior view of run_command beside its source](/images/code-map-behavior.png "Code map with a diff overlay: changed declarations are outlined in red, and the Behavior view shows each branch and early return.")

## The tests go looking for bugs

Property tests draw inputs nobody thought of and shrink any failure to a small case. `ms test --fuzz 30s` turns the same tests into a fuzzer. The agent's code meets odd inputs before your users do.

## Hardened with frontier models

Manuscript is young, and the project is hardened with frontier models. We use them to find edge cases, bugs, memory leaks and performance regressions, and to fix them.

The method is simple. For correctness, a model probes one area at a time: it writes programs against new features and their edges, compares what happens with the documented rule, and fixes real bugs with regression tests. For performance, it starts from a measured gap, reproduces it, changes one thing, and shows before and after on the same machine. A fix that costs more than it earns is dropped.

## Fast to iterate, fast to ship

The compiler is a pipeline that gets slower and smarter at each step:

```text
Manuscript source -> HIR -> MIR -> CLIF -> LLVM
```

The early stages are far cheaper than the late ones, so you stop as early as the task allows. Check while you write, run a quick debug build to try it, and pay for LLVM only when you ship. As a program matures you can spend more of the pipeline on it, and the optimizations that earn their cost are the ones you keep. An agent that runs the compiler dozens of times per task lives in the cheap stages; the binary you deploy comes out of the expensive ones.

On a generated 122,000-line project (40 packages, cold build, 4 vCPUs):

| step | time |
|---|---:|
| `ms check` (parse and type-check) | 2.2 s |
| `ms build` debug (Cranelift) | 5.4 s |
| `go build` | 9.0 s |
| `ms build --release` (LLVM) | 43.6 s |

A debug build is 1.7 times faster than Go's cold build, and a check is four times faster. The release build is the slow path on purpose: it spends the time on optimization, so compare it with other optimizing builds rather than with Go's. We have not yet measured the same project against Rust, so this page makes no compile-time claim about it. The numbers come from the [2026-11-05 results](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/results-2026-11-05.md), which name the revision, machine and command. Release builds produce a native executable that runs without Manuscript installed.

## We measure it with agents

The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) gives agents the same challenges in TypeScript, Go, Rust and Manuscript and grades them on hidden tests. What goes wrong there decides what we build next. Every result types its revision and machine.

## Where it stands

The language core, the `ms` toolchain and the standard library work today. Syntax and APIs still evolve, and each release hardens them further. The [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) describes where this is heading.

**Next:** [Run your first program](getting-started.md)
