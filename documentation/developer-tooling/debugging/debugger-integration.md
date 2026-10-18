+++
title = "Debugger transport and source interpretation"
weight = 120
+++

# Debugger transport and source interpretation

Delve provides the transport. `internal/debugger` only embeds it; Manuscript value interpretation lives in the VS Code adapter.

## Embedded debugger

- `ms debug main.ms -- argument` builds Debug code and runs Delve's terminal inside `ms`.
- The VS Code adapter starts `ms dap`, which serves one DAP session over private stdin/stdout pipes. Disconnect, connection loss, or termination stops the service and reaps a launched target. Only `manuscript.serverPath` is needed; `manuscript.delvePath` is obsolete.
- Delve v1.25.2 is pinned and vendored. Manuscript imports the public [`service/dap`](https://github.com/go-delve/delve/blob/v1.25.2/service/dap/server.go), `service/rpccommon`, `service/rpc2`, and `pkg/terminal` packages, which sit outside Delve's `internal` directories ([Go's internal-package rule](https://go.dev/doc/go1.4#internalpackages)).
- Launches use `outputMode: "remote"` so output arrives as DAP events; local target output goes to stderr. Target stdin is the null device, so the protocol pipe is never application input.
- The terminal uses an in-process RPC pipe with no network socket. No `dlv` is spawned, downloaded, or extracted. Vendored source and license notices ship in the binary.

| Distribution | Debugger backend and prerequisites |
| --- | --- |
| Linux AMD64/ARM64 | In-process native backend; OS/container policy must permit tracing the child process |
| Windows AMD64 | In-process native backend; OS permission to debug the child process |
| Windows ARM64 | Upstream experimental native backend, enabled in packaged builds with `exp.winarm64`; OS permission to debug the child process |
| macOS AMD64/ARM64 | Delve's default LLDB backend launches Apple's signed `debugserver` from Xcode command line tools; macOS debugger authorization still applies |

- All distributions keep `CGO_ENABLED=0`. Windows ARM64 source builds that import the debugger also need `-tags=exp.winarm64`; `make build` and packaging include it.
- On macOS, embedding Delve does **not** make debugging self-contained: upstream disables its native backend without `macnative` (CGO, known limitations). Manuscript does not bundle Apple tools or change signing, entitlements, or OS security. Delve reports missing tools. See the pinned [backend selection](https://github.com/go-delve/delve/blob/v1.25.2/service/debugger/debugger.go) and [installation guidance](https://github.com/go-delve/delve/blob/v1.25.2/Documentation/installation/README.md).
- `make dist-check` runs a copied binary with empty caches, no Go or `dlv` on PATH, and downloads disabled, checking breakpoints, stepping, locals, disconnect, and transport-loss cleanup in both terminal and DAP. On macOS it verifies the `debugserver` prerequisite.

## DAP behavior

- A failed `attach` leaves no session; the next `launch` or `attach` starts clean.
- Session requests (`pause`, `continue`, `next`, `threads`, `setBreakpoints`, and the rest) before a successful `launch` or `attach` get the DAP error `no debug session: send launch or attach before <command>`.
- After the target exits, `continue`, `next`, `stepIn`, `stepOut`, and `pause` get the error `the debuggee has exited`. `terminate` is accepted in every state and ends the session like `disconnect` with `terminateDebuggee`. An `exited` event precedes `terminated` only when the exit code is known.
- Launch requests must use `mode: exec` with a compiled target; build with `ms build --debug`. Delve's Go-source build and test modes are rejected.
- Source maps supply paths instead of Go-module guessing; explicit `substitute-path` rules remain available.

## Scripted debugging for agents

`ms debug` without options opens Delve's terminal (prompts, ANSI colors, Go-level names). For agents and scripts, two options run the same Delve service without a terminal:

```sh
ms debug ms.toml --break src/main.ms:7 --json -- first second
ms debug ms.toml --script commands.txt
```

- `--break <location>` (repeatable) installs breakpoints, runs to the first stop, reports it, kills the program, and exits. A rejected breakpoint ends setup before the program runs. Exit 1 if setup fails or the program ends without a stop.
- `--script <file>` (or `-` for stdin) runs one command per line; blank lines and `#` lines are ignored. EOF and `exit` end the session and kill the target. A failed command reports an error, makes the final status 1, and the script continues. Input or event-output failures end the session with status 1; their diagnostics are best effort.
- `--json` prints one JSON object per line on stdout: `breakpoint`, `stop`, `stack`, `locals`, `value`, `cleared`, `breakpoints`, `exit`, and `error` events. The program's own output goes to stderr. Without `--json` the same events print as plain text with no prompts or ANSI escapes.
- Only for `ms debug`, which always builds Debug. Program stdin is the null device.

| Script command | Effect |
| --- | --- |
| `break <location>`, `clear <id>`, `breakpoints` | Add, remove, list breakpoints |
| `continue`, `next`, `step`, `stepout` | Run or step |
| `stack`, `locals`, `print <name>` | Inspect |
| `exit` | End the session |

A location is `file:line` (relative to the project or source root, or absolute) or a function name, which stops at its first statement. A name declared in several modules is ambiguous; use `file:line`.

A `stop` event gives the function, file, line, source line, stack, and locals. Only `.ms` frames appear. Locals use source names and `.ms` types from `ms inspect`; temporaries are hidden. Strings and scalars print their values; records, collections, and variants use Delve's one-line form. After a step, the debugger skips lines no statement owns and Go runtime frames, so every stop is a program statement.
