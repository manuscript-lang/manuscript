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
on PATH, and Go downloads disabled. It checks scripted source names/values and
filtered/raw stacks, the terminal, and native DAP
breakpoints, stepping, locals, disconnect, and transport-loss cleanup. On macOS
it also verifies the installed system debugserver prerequisite; it cannot claim
an installation with no Apple developer tools works.

DAP launch requests must use `mode: exec` with an already compiled target. Compile Manuscript with `ms build --debug`; Delve’s Go-source build/test modes are rejected before tool discovery.

Go-module source-path guessing is not used for Manuscript targets; source maps provide their paths, and explicit `substitute-path` rules remain available. The vendored Delve compatibility probe for pre-Go-1.11 builds is disabled; dependency refresh reapplies this patch.

## Scripted debugging

Use `--script commands.txt --json` for a JSONL transcript. With no script flags,
`ms debug` continues to run the interactive Delve terminal. The source or project
argument comes first, and application arguments go after `--`:

```sh
cd examples/hello
cat > commands.txt <<'EOF'
break main
continue
next
locals
print message
bt 3
bt 20 --raw
continue
exit
EOF
ms debug ms.toml --script commands.txt --json -- a b
```

Existing project pins still apply; run `ms lock ms.toml` explicitly if the build
reports a stale pin. At the source stop, `message` renders as a `String` with value
`"Arguments: 2\n"`. Program output appears in an `output` record with
`stream: "stdout"`. `--script -` reads commands from stdin; the application reads
the null device so it cannot consume debugger commands. Both `--script` and
`--json` are required for scripted mode. `--raw-stack` includes native frames in
all scripted stacks.

Scripted mode requires an OS handle that remains bound to the launched process
after it exits: Linux uses explicit pidfds and rejects kernels/policies without
the required pidfd signal/wait APIs; Windows uses a retained process handle.
Scripted mode is currently rejected on other platforms, including macOS, where
the available PID-only interruption cannot meet that guarantee. Interactive
`ms debug` and editor DAP retain their existing platform support.
Windows console stdin is rejected before launch because its blocking read cannot
be cancelled safely; use a script file or redirected pipe for `--script -`.

Commands are one per line. Blank lines and lines beginning with `#` are ignored;
the command ID is its original line number. There is no shell quoting or inline
comment syntax; everything following `break` is the location, including spaces
in a file name.

| Command | Behavior |
| --- | --- |
| `break location` | Resolve a source function name or a Delve location such as `src/main.ms:5` |
| `continue`, `next`, `step`, `step-out` | Use the corresponding native Delve execution operation |
| `locals` | Render checked source locals and parameters in the selected native frame |
| `print name` | Render one unambiguous visible source local or parameter; expressions are deferred |
| `bt [depth] [--raw]` | Show source frames by default, or include native frames with `--raw`; default depth 20, maximum 256 |
| `exit` | Kill and reap the launched target, then end the session |

Source function breakpoints use checked declaration metadata and the first body
statement, avoiding the generated launcher. A duplicate name reports candidates
such as `src/a.ms:answer` and `src/b.ms:answer`; use that exact `file:name` spelling
to select one. A function without a body statement fails rather than binding a
later declaration. When an entry line maps to multiple native functions (for
example a generated factory and its callable), the named breakpoint reports that
ambiguity; an explicit file:line keeps Delve's ordinary line-breakpoint behavior.
A source statement without a native instruction can still be
rejected by Delve. Unrecognized source names retain native Delve location syntax.

Each record has `version: 1`, a monotonically increasing `seq`, and `event`.
Successful execution follows this order: `command`, any checkpoint `output`,
`result`, then `stop` for an execution operation that stopped. The native entry
stop precedes commands and includes the launched `pid`. Explicit `exit` produces
a `command` followed by the final `exit`, without a result. Natural target exit
ends the session immediately, leaving later input unused.

| Event | Fields |
| --- | --- |
| `command` | `command_id` and the original `command` text |
| `result` | `command_id`; `result` contains a breakpoint ID/location, values, or stack frames, as applicable |
| `stop` | `reason` (`entry`, `breakpoint`, or `step`), actual `location`, available source `locals`, and `stack` (depth 20); `stack_truncated: true` marks a limit; later stops include `command_id` |
| `output` | `stream` (`stdout` or `stderr`) and either `text` or lossless `bytes_base64` |
| `error` | Stable stage `code`, explanatory `message`, and `command_id` when associated with input |
| `exit` | `reason`, debugger `status`, and nullable `target_status` |

`target_status` is null except when the target exited naturally. Exit reasons are
`exited`, `exit`, `eof`, `cancelled`, or `error`. Natural exit returns the target's
status; explicit exit and EOF return 0; debugger errors and cancellation return
1. Error codes are `compile`, `build`, `execution`, `metadata`, `launch`, `input`,
`command`, `debugger`, `state`, `inspection`, `output`, `cleanup`, or `cancelled`.
Malformed commands and debugger failures end the session. Pre-session source,
build, and setup failures emit `error` then `exit`; CLI usage errors retain stderr
diagnostics and status 2. Broken protocol output can prevent final records from
being delivered, but target cleanup still runs. Cancellation closes owned
Windows output handles to interrupt synchronous writes; those pipes may lack final
records.

Frames retain their native `index`, `native_function`, and a `source` flag.
Source frame file names are relative to the validated build source root;
embedded standard source names retain their `@std/` identity and are verified
against the pinned bundle, not against a physical file in the project.
native frames keep Delve's paths. Source stacks are selected from validated
inspection files and scan at most 256 native frames. `bt` reports `truncated`
when its depth or scan limit is reached. Unwind failures produce an error
instead of an apparently complete stack. Closures use their enclosing declaration
as a display label and retain native identity. Stepping can stop inside runtime
code: the stop location remains that actual native location, and `locals`/`print`
require a source frame. Source-aware stepping and concurrency-service inspection
are deferred.

Values unwrap native interfaces and pointers and use checked names/types, with
source views for primitives, unit, records, alternatives, lists, sets, maps, and
bytes. Views are bounded to three child levels, 32 collection entries and 512
string bytes. `truncated` and `unavailable` preserve missing data; native slots
that no longer hold a declared container are marked unavailable after last use.
Unsupported service values retain a type summary.
Map children include a separate `key` view that retains the key's `truncated`
and `unavailable` markers; the child `name` is only a display label. Distinct keys
can share the same clipped display prefix. Incomplete keys also mark the map view
`truncated`, so its displayed keys cannot be treated as complete identities.

Output is captured in private files and delivered at command/stop and shutdown
checkpoints, with stdout before stderr at each checkpoint. It is not delivered
live during a running command, and ordering across the two streams is not a
program execution order. Chunks are at most 8192 bytes; clients must decode and
concatenate `bytes_base64` as bytes, which also preserves UTF-8 split across chunk
boundaries and non-text output.

EOF completes pending inspection commands and then cleans up. If a final
execution command is unfinished and no later command remains, EOF cancels that
operation through the retained OS identity, joins Delve, and reaps it before
closing input; it does not produce a successful
result for the interrupted command. A completed response takes precedence when
already available. Keep an explicit `exit` after a resume command to wait for its
stop or natural exit. SIGINT/SIGTERM, reader/writer errors, and cancellation also
clean up launched targets.
