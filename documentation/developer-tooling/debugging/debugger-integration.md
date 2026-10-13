+++
title = "Debugger transport and source interpretation"
weight = 120
+++

# Debugger transport and source interpretation

The debugger design has two parts: Go tools control execution, while a Manuscript layer explains source values, concurrent operations, and generated frames. A native line number alone cannot explain a source alternative or a cleanup frame.

Delve DAP provides native debugger transport; a Manuscript debugger layer renders source values and marks generated cleanup and runtime frames. Native line mapping alone does not provide that interpretation.

## Embedded debugger

`ms debug main.ms -- argument` builds Debug code and runs Delve’s terminal in
`ms`. The VS Code adapter starts `ms dap`, which serves one DAP session over
stdin/stdout using private editor pipes. Disconnect, connection loss,
or termination stops the service and reaps a launched target. The adapter keeps
its existing source maps, checked names, value rendering, and stepping protocol.
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

DAP launch requests must use `mode: exec` with an already compiled target. Compile Manuscript with `ms build --debug`; Delve’s Go-source build/test modes are rejected before tool discovery.

Go-module source-path guessing is not used for Manuscript targets; source maps provide their paths, and explicit `substitute-path` rules remain available. The vendored Delve compatibility probe for pre-Go-1.11 builds is disabled; dependency refresh reapplies this patch.


## Inspecting TaskGroup, Scheduler, and with

The required debug conformance program steps through API admission, concurrent operations, joining, and cleanup. It must demonstrate source stepping, value rendering, and operation and service inspection together; native line mapping alone cannot establish that behavior.

See [complete-program evidence](../../contributing/compiler/conformance/programs.md), [metadata](metadata.md), and [Go line mapping](source-mapping.md).
