# Tooling demo

This project exercises typed completions, source navigation/refactoring, native debugging, and profiling. Build `ms`, install the [VS Code extension](../../extensions/vscode/README.md), install Delve, and open this folder in a trusted workspace. Set executable paths in VS Code if `ms` and `dlv` are not on PATH.

```sh
ms lock ms.toml
ms check ms.toml
ms test ms.toml
ms run ms.toml
ms profile ms.toml -o captures --trace
ms profile src/work.ms -o work-captures
ms pprof -tags work-captures/cpu.pprof
ms pprof -http=127.0.0.1:8080 captures/program captures/cpu.pprof
ms trace captures/trace.out
```

Set a breakpoint on the workload call in `src/main.ms` and press F5. Inspect the record, list, variant, queue, and execution scopes; add `package.count` as a watch. `src/lint.ms` contains semantic lint findings. Add trailing spaces and remove its final newline to also demonstrate the two source-hygiene findings; use it for diagnostics, quick fixes, and formatting. Profile destinations must be new.
