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

## A pipeline built for fast iteration and fast binaries

The compiler is a ladder of stages. Each stage lowers the program to a representation closer to the machine, and each costs more than the one before it:

```text
Manuscript source -> HIR -> MIR -> CLIF -> LLVM IR
```

1. **Source to HIR.** `ms check` parses and type-checks the program into a typed high-level IR, and reports diagnostics, without building anything. It is the fastest stage, and an agent can run it after every edit.
2. **HIR to MIR.** Lowering makes ownership, moves and drops explicit in a mid-level IR, where the optimizer and verifier run.
3. **MIR to CLIF.** Debug builds hand MIR to Cranelift, which produces working native code quickly. This is the edit-check-run loop.
4. **MIR to LLVM.** Release builds (`ms build --release`) hand the program to LLVM, which spends the most time and produces the fastest code.

The early stages are much faster than the later ones, so most iterations stop early: check while you write, run the Cranelift build to try it, and pay for LLVM only when you ship. As a program matures you can spend more of the pipeline on it, adding optimization where it earns its cost. The result is a compiler designed for fast iteration that still produces fast production binaries. `ms build --release` yields a native executable that runs without Manuscript installed.

## We measure it with agents

The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) gives agents the same challenges in TypeScript, Go, Rust and Manuscript and grades them on hidden tests. What goes wrong there decides what we build next. Every result types its revision and machine.

## Where it stands

The language core, the `ms` toolchain and the standard library work today. Syntax and APIs still evolve, and each release hardens them further. The [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) describes where this is heading.

**Next:** [Run your first program](getting-started.md)
