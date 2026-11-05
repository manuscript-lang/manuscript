+++
title = "Profiling and native debugging"
weight = 120
+++

# Profiling and native debugging

Use a repeatable input to review where work happens; save this as `words.ms`.

## Prepare a repeatable workload

<!-- manuscript-example: {"mode":"run","stdout":"12\n","args":["2"],"filename":"words.ms"} -->
```manuscript {filename="words.ms"}
import arguments from "@std/os/process.ms"

fn count_words(text: String) Int:
    return text.split(" ").length()

fn repetition_count() Int!:
    let args = arguments()
    if let text = args.first():
        return ok(try text.parse_int().ok_or(Error("expected an integer")))
    return ok(1000000)

fn run() Unit!:
    let repeats = try repetition_count()
    var total = 0
    for index in 0..repeats:
        total += count_words("small programs are easy to review")
    print(total)
    return ok(unit)

export fn main() Int:
    match run():
        ok(_):
            return 0
        error(cause):
            print(cause.message)
            return 1
```

```sh
ms run words.ms -- 2
```

```text
12
```

- Invalid integer arguments print `expected an integer` and exit 1.
- Manuscript is in alpha; syntax, APIs and profiling output may change.

## Capture a profile {#profiling-with-ms-profile}

```sh
ms profile words.ms --out-dir capture --top 10 -- 1000000
```

```text
6000000
```

- Shown above is application output; a variable sampling report follows. Use a new capture directory each time.
- `profile` runs `main` in `Release` by default; it returns the program's status. Measure unprofiled execution separately.

## Read the capture

- Open `capture/top.txt`: `flat` counts innermost samples; `cum` includes callees. Counts are samples, not exact calls.
- Use `profile.folded` or `profile.pb` in compatible viewers; keep `program` and `manifest.json` with the capture.

## Stop at a source line with LLDB

In a POSIX terminal:

```sh
ms build words.ms --build-type Debug -o words
./words 2
lldb ./words
```

```text
Built words
12
```

- The output shown is from build/run; LLDB starts its own prompt and requires a separate installation.

LLDB commands, using the return statement at line 4:

```text
breakpoint set --file words.ms --line 4
breakpoint list
run 2
thread backtrace
source list
thread step-out
thread step-over
breakpoint disable
continue
```

- Confirm a resolved breakpoint before running; after stepping, `continue` finishes and the program prints `12`.
- File/line maps omit Manuscript variables, types and inline frames; optimized code can move or disappear.

## Source attribution

- macOS source lookup needs `dsymutil` at build time and the adjacent `.dSYM`; Linux keeps line maps in the executable.
- On Windows build `words.exe`, run `.\words.exe 2`, and use a DWARF-capable debugger; no PDB is emitted.


Next: [LLDB commands](https://lldb.llvm.org/use/tutorial.html), [GDB commands](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Sample-Session.html), [code maps](../implementation.md#interactive-code-map) and [benchmarks](../../learn/testing.md#benchmark-your-code).
