+++
title = "CLI application hosts"
weight = 46
+++

# CLI application hosts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The CLI host has a fixed entry contract. The selected entry module must export exactly one nongeneric `fn main(process: Process) -> Int`; other exports are permitted. Missing/internal main or any different label/type/result is a compile error. The host creates one run context, constructs Process, invokes main once, and waits for work and cleanup before reporting exit.

## Explicit authority roots

`Process` is a standard immutable record:

```text
type Process:
    arguments: List[String]
    environment: Map[String, String]
    stdin: ReadStream & Shareable
    stdout: WriteStream & Shareable
    stderr: WriteStream & Shareable
    files: Files & Shareable
    clock: Clock & Shareable
    network: Network & Shareable
    commands: Commands & Shareable

interface Clock:
    fn now() -> Instant

interface Files:
    fn open(path: String) -> Result[File & Shareable, IoError]
```

Arguments exclude the executable name. Environment is a snapshot; duplicate OS names are resolved by the host before entry. Invalid UTF-8 in process inputs is a startup failure on native stderr with exit 70 before main runs. Relative file paths use the fixed startup working directory. The specified file API opens read-only files; file creation remains an additional API contract. Network and command operations are specified in [HTTP](http.md) and [subprocess execution](../data-and-io/streams.md).

The host creates Files, Clock, and stdio behind shared views. Those field types make Process shareable; Files.open preserves sharing in its returned File view. Applications and source fakes follow the same [view-conversion rules](../../core-language/types/contracts.md#shared-contract-views).

Importing an interface supplies no authority. Files, clock, stdio, and environment arrive only through Process. The host closes roots after main and its scoped services finish; the application registers acquired files with `with`. Early root-stream closure affects every alias.

```text
import Process from "@std/cli.ms"

export fn main(process: Process) -> Int:
    let message = "Arguments: {process.arguments.length()}\n"
    match process.stdout.write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
```

This is a complete entry module. Only the Process type name is imported; field/method results and match cases are inferred from its public signatures. The import supplies the interface, while the host supplies the authority-bearing value. On success its transcript is `Arguments: N` followed by LF and exit 0. Stream signatures are defined in [streams](../data-and-io/streams.md).

## Exit and shutdown

Normal main results must be 0–125; other results fault. An unhandled root or cleanup fault exits 70 after attempted cleanup and reports primary/secondary diagnostics on host stderr. SIGINT/SIGTERM request cancellation; after joining and cleanup SIGINT exits 130 and SIGTERM exits 143. The first accepted stop reason is retained; a fault during joining/cleanup takes precedence and exits 70. Parent cancellation unwinds main rather than becoming a normal Result.

The `ms run` launcher forwards SIGINT/SIGTERM to the native host and waits for its joined shutdown before reporting that exit status.

Construct application Background services in main with `with`, inside their dependencies' scopes. Shutdown stops admission, joins services, then releases roots. Uncooperative work/reporters can require [host escalation](../../concurrency/runtime.md#host-escalation); the host exposes its watchdog policy. Escalated exit is incomplete cleanup, not conformance success.

## Additional explicit roots

`Process` also exposes `network: Network & Shareable` and `commands: Commands & Shareable` for the [bounded HTTP host](http.md) and [bounded subprocess execution](../data-and-io/streams.md). These capabilities are synchronized host roots. Network services register under their construction execution and join before host roots are released. The host provides no ambient networking or process constructor.
