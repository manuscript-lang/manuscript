+++
title = "Profiling and native debugging"
weight = 120
+++

# Profiling and native debugging

Use `ms profile` to find where a program spends CPU time. Build an unoptimized executable when you want to stop at a source line and follow execution with a native debugger. Start with the same input that reproduces the behavior you are investigating.

## Prepare a repeatable workload

Save this as `words.ms`. It splits a short line repeatedly and prints the number of words processed. The argument controls how much work to do:

<!-- manuscript-example: {"mode":"run","args":["2"],"stdout":"12\n"} -->
```manuscript
import arguments from "@std/os/process.ms"

fn count_words(text: String) Int:
    return text.split(" ").length()

export fn main() Int:
    let repeats = arguments().get(0, default: "1000000").parse_int().get(1000000)
    var total = 0
    for index in 0..repeats:
        total += count_words("small programs are easy to review")
    print(total)
    return 0
```

```sh
ms run words.ms -- 2
```

```text
12
```

For your own application, use its real entry point and representative data. `ms profile` runs `main`, not test or benchmark blocks.

## Capture a profile {#profiling-with-ms-profile}

```sh
ms profile words.ms --out-dir capture --top 10 -- 1000000
```

The program prints `6000000`, followed by a summary of sampled functions and the bundle location. `capture` must be a new directory; choose another name for the next run. The default build is optimized `Release`, so you profile the code you would ship. Arguments after `--` reach the program, and the command returns the program's exit status.

Open `capture/top.txt` to read the same report again. Its columns are:

```text
    flat   flat%      cum    cum%  function
```

- **flat** counts samples where this function was the innermost frame: start here to find work done directly in a function.
- **cum** counts samples whose stack contains the function, including its callees: use this to find callers responsible for expensive work.
- The percentages use the total sample count. Counts and rankings vary between runs; they are not exact call counts or elapsed wall-clock measurements.

This example spends much of its work splitting and allocating strings, so `[runtime]` may lead the flat report while `main` has cumulative samples. Optimization can inline the small `count_words` helper. A very short run may collect no samples: increase the representative workload before drawing conclusions. Measure normal execution separately because profiling adds overhead.

The bundle keeps the executable and data for further investigation:

| File | Use |
| --- | --- |
| `program` | Rerun the exact profiled executable. |
| `top.txt` | Read the ranked function report. |
| `profile.folded` | Load folded stacks into a compatible flamegraph viewer. |
| `profile.pb` | Open the profile in a pprof-compatible viewer. |
| `manifest.json` | Find artifact names, sampling frequency and sample count. |

Use `--json` when another tool needs the versioned result instead of terminal prose. On Linux, the command also prints a `perf record` invocation for the executable; using it requires an installed `perf` and permission to sample processes.

## Stop at a source line with LLDB

Use an installed [LLDB](https://lldb.llvm.org/use/tutorial.html) and keep `words.ms` beside your working directory. Build without optimization so source stepping follows the program more closely:

```sh
ms build words.ms --build-type Debug -o words
./words 2
```

```text
Built words
12
```

Launch the native executable:

```sh
lldb ./words
```

At the LLDB prompt, set a file/line breakpoint on the return statement inside `count_words` (line 4 in the file above), confirm that it has a resolved location, then run a small input:

```text
breakpoint set --file words.ms --line 4
breakpoint list
run 2
```

Once stopped, inspect the call stack and source, then move back to the caller:

```text
thread backtrace
source list
thread step-out
thread step-over
breakpoint disable
continue
```

The final `continue` lets the program finish and print `12`. File/line breakpoints select your code directly; a breakpoint named `main` can instead select the native startup wrapper. Generated symbol names may have suffixes, so do not guess them from Manuscript declarations. If a breakpoint has no locations, check the filename and line against the source used for that build and rebuild after edits.

With [GDB](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Sample-Session.html), start `gdb ./words`, then use `break words.ms:4`, `run 2`, `backtrace`, `list`, `finish`, `next`, `disable breakpoints`, and `continue` for the same workflow.

## What source information is available {#source-attribution}

Native builds retain frame pointers and DWARF file/line mappings. These support source breakpoints, stack attribution and stepping; optimized code can reorder or remove operations. The emitted debug information does not describe Manuscript local variables, types or inline call frames. Use source-level `print` calls or a focused test to inspect a value, rather than relying on a debugger expression evaluator to understand it.

On macOS, keep the adjacent `words.dSYM` bundle with the executable. `ms build` creates it when `dsymutil` is available; without it the executable runs but source line lookup is unavailable. On Windows, name the output `words.exe` and use a debugger that can read its DWARF information; the compiler does not emit a PDB. Linux keeps the line information in the executable itself.

To investigate which functions can call each other before running, open an [interactive code map](../implementation.md#interactive-code-map). To compare an optimization with repeatable measurements, use [benchmarks](../../learn/testing.md#benchmark-your-code).
