+++
title = "Profiling and native debugging"
weight = 120
+++

# Profiling and native debugging

The Rust `ms` has no embedded debugger: `ms debug`, `ms dap`, and the VS Code debug adapter are not part of it. `ms profile` and the debug information that native builds keep take their place.

## Source attribution

- Native builds keep frame pointers and emit DWARF line tables for file and line lookup, including optimized code. They do not describe variables, types, or inline call frames.
- `--build-type Debug` disables optimization for a build.
- Faults report source frames from the line tables, and `perf record` works on any `ms build` output because the compiler also emits a perf map.
- On macOS, `ms build` writes `<output>.dSYM` beside the executable; keep that bundle with the executable for source lookup.

## Profiling with `ms profile`

```sh
ms profile ms.toml --out-dir capture --top 10 -- first second
```

`ms profile` builds the application, runs it with the sampling profiler enabled, and writes a new directory containing `program`, `profile.folded`, `profile.pb` (pprof), `top.txt`, and `manifest.json`. Arguments after `--` go to the application, and its exit status is returned. `--json` emits one versioned result. Profiling adds overhead, so measure normal execution separately.

An external native debugger such as `gdb` or `lldb` can read the DWARF line tables of an `ms build` output, but Manuscript provides no value interpretation for it.
