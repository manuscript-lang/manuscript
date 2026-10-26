# Tooling demo

This project exercises typed completions, source navigation/refactoring, lint fixes, and native profiling. Build `ms`, install the [VS Code extension](../../extensions/vscode/README.md), and open this folder. Set `manuscript.serverPath` in VS Code if `ms` is not on PATH.

```sh
ms check ms.toml
ms test ms.toml
ms run ms.toml
ms profile ms.toml --out-dir captures --top 10
ms profile src/work.ms --out-dir work-captures --top 10
```

Profile destinations must be new. Each bundle contains `program`, `profile.folded`, `profile.pb`, `top.txt`, and `manifest.json`. Read `captures/top.txt` for the text report or open `captures/profile.pb` with an external pprof viewer. See [profiling and native debugging](../../documentation/developer-tooling/debugging/debugger-integration.md) for the bundle format and debugger support.

Use completion and hover on `package` in `src/main.ms`, follow `total` or `compute` to `src/math.ms`, and rename local declarations. `src/lint.ms` deliberately contains semantic lint findings for diagnostics and quick fixes. Add trailing spaces or remove its final newline to demonstrate the two source-hygiene findings and formatting.
