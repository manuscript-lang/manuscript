+++
title = "Debugger transport and source interpretation"
weight = 120
+++

# Debugger transport and source interpretation

Delve provides debugger transport. `internal/debugger` only embeds Delve; Manuscript value interpretation lives in the VS Code adapter.

## Embedded debugger

`ms debug main.ms -- argument` builds Debug code and runs Delve’s terminal in
`ms`. The VS Code adapter starts `ms dap`, which serves one DAP session over
stdin/stdout using private editor pipes. Disconnect, connection loss,
or termination stops the service and reaps a launched target.
Only `manuscript.serverPath` is needed; `manuscript.delvePath` is obsolete.

Delve v1.25.2 is pinned and vendored. Manuscript imports the public
[`service/dap`](https://github.com/go-delve/delve/blob/v1.25.2/service/dap/server.go),
`service/rpccommon`, `service/rpc2`, and `pkg/terminal` packages.
DAP uses `NewSession`/`ServeDAPCodec`/`Close` directly, joining the request loop
before exit. Launches use `outputMode: "remote"` for DAP output events; any local
target output goes to stderr so it cannot corrupt the protocol. Target stdin is
redirected to the null device, as with the previous editor adapter; the protocol
input pipe must never be inherited as application input. These paths are
outside Delve’s `internal` directories: [Go’s internal-package rule](https://go.dev/doc/go1.4#internalpackages)
would forbid importing those implementation directories directly. The terminal
uses an in-process RPC pipe, with no listening network socket. No `dlv` process
is spawned, downloaded, or extracted. Vendored source and license notices are
included in the binary and distribution license directory.

| Distribution | Debugger backend and prerequisites |
| --- | --- |
| Linux AMD64/ARM64 | In-process native backend; OS/container policy must permit tracing the child process |
| Windows AMD64 | In-process native backend; OS permission to debug the child process |
| Windows ARM64 | Upstream experimental native backend, enabled in packaged builds with `exp.winarm64`; OS permission to debug the child process |
| macOS AMD64/ARM64 | Delve’s default LLDB backend launches Apple’s signed `debugserver` from Xcode command line tools; macOS debugger authorization still applies |

All distributions retain `CGO_ENABLED=0`. Windows ARM64 source builds/tests that
import the debugger must also pass `-tags=exp.winarm64`; `make build` and the
packaging script include it. On macOS, embedding Delve does **not**
make native debugging entirely self-contained: upstream disables its native
backend without `macnative`, whose implementation uses CGO and has known
limitations. The supported default is Apple’s separately installed debugserver.
Manuscript does not bundle or download Apple tools, create signing identities,
change entitlements, or change OS security settings. Missing platform tools are
reported by Delve. See the pinned [backend selection](https://github.com/go-delve/delve/blob/v1.25.2/service/debugger/debugger.go)
and [installation guidance](https://github.com/go-delve/delve/blob/v1.25.2/Documentation/installation/README.md).

`make dist-check` exercises a copied binary with empty caches, no Go or `dlv`
on PATH, and Go downloads disabled. It checks the terminal and native DAP
breakpoints, stepping, locals, disconnect, and transport-loss cleanup. On macOS
it also verifies the installed system debugserver prerequisite; it cannot claim
an installation with no Apple developer tools works.

A failed `attach` leaves no session behind: the next `launch` or `attach` starts from a clean target selection instead of retrying the earlier process id.

Requests that need a debug session (`pause`, `continue`, `next`, `threads`, `setBreakpoints`, and the rest) sent before a successful `launch` or `attach` get an ordinary DAP error response, `no debug session: send launch or attach before <command>`, instead of reaching Delve, which dereferences a missing debugger on `pause`.

DAP launch requests must use `mode: exec` with an already compiled target. Compile Manuscript with `ms build --debug`; Delve’s Go-source build/test modes are rejected before tool discovery.

Go-module source-path guessing is not used for Manuscript targets; source maps provide their paths, and explicit `substitute-path` rules remain available. The vendored Delve compatibility probe for pre-Go-1.11 builds is disabled; dependency refresh reapplies this patch.

## Scripted debugging for agents

`ms debug` without options opens Delve's terminal, which prints prompts, ANSI colors, and Go-level names. For agents and scripts, two options run the same embedded Delve service without a terminal:

```sh
ms debug ms.toml --break src/main.ms:7 --json -- first second
ms debug ms.toml --script commands.txt
```

- `--break <location>` (repeatable) installs breakpoints, runs to the first stop, reports it, kills the program, and exits. It exits 1 if the program ends without reaching a breakpoint.
- `--script <file>` (or `-` for standard input) runs one command per line; blank lines and lines starting with `#` are ignored. Commands: `break <location>`, `clear <id>`, `breakpoints`, `continue`, `next`, `step`, `stepout`, `stack`, `locals`, `print <name>`, and `exit`. A failed command reports an error and makes the final status 1; the script continues.
- `--json` prints one JSON object per line on standard output: `breakpoint`, `stop`, `stack`, `locals`, `value`, `cleared`, `breakpoints`, `exit`, and `error` events. The program's own output goes to standard error so standard output stays parseable. Without `--json` the same events print as plain text with no prompts or ANSI escapes.
- A location is `file:line` (relative to the project or source root, or absolute) or the name of a function declared in Manuscript source. A function name stops at its first statement; a name declared in more than one module is ambiguous, so use `file:line`.

A `stop` event names the Manuscript function, file, and line, the source line, the stack, and the locals. Only frames in `.ms` source appear in the stack. Locals use their source names and `.ms` types from `ms inspect`; generated temporaries are hidden. A string prints its text and a scalar its value. Records, collections, and variants appear in Delve's one-line form because only the VS Code adapter renders them as Manuscript values. After `next`, `step`, or `stepout`, the debugger keeps stepping past lines that no statement owns (generated position bookkeeping) and past Go runtime frames, so each stop is a statement line of the program.

The program's standard input is the null device, as with `ms dap`. These options are valid only for `ms debug`, which always builds with the Debug build type.
