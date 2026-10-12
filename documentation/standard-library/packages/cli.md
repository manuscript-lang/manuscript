+++
title = "Command-line programs"
weight = 57
+++

# Command-line programs

[Guide index](../_index.md) · [Package index](_index.md) · [Design index](../../_index.md)

A CLI application starts at an exported `fn main() -> Int`. The host creates the execution context and host services, calls main once with no arguments, then waits for work and cleanup before reporting the exit code.

The selected entry module must export exactly one nongeneric main with no parameters and an Int result. Missing or internal main, or a different signature, is a compile error. Other exports are allowed.

## Importing host services

Import the accessor for each service an application uses. Accessors are ordinary zero-parameter functions backed by the current execution's host services:

| Import from | Accessors |
| --- | --- |
| `@std/cli.ms` | `arguments() -> List[String]`, `environment() -> Map[String, String]` |
| `@std/io.ms` | `stdin() -> ReadStream`, `stdout() -> WriteStream`, `stderr() -> WriteStream`, `files() -> Files` |
| `@std/fs.ms` | `filesystem() -> FileSystem` |
| `@std/net.ms` | `network() -> Network` |
| `@std/process.ms` | `commands() -> Commands`, `control() -> ProcessControl` |
| `@std/time.ms` | `clock() -> Clock`, `wall_clock() -> WallClock` |
| `@std/random.ms` | `entropy() -> Entropy` |
| `@std/system.ms` | `system() -> System` |

Type names and functions still require explicit imports when named in source. Importing an accessor does not add other declarations to scope. Calling it returns the existing service; repeated calls do not construct new roots. Helpers, callbacks, task-group work, and imported modules use the services of their invocation execution. Scheduler services retain their construction execution's services.

```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"
    match stdout().write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
```

On success this program prints `Arguments: N` followed by LF and exits 0. Stream signatures are defined in [streams](../data-and-io/streams.md).

Arguments exclude the executable name. Environment is a startup snapshot; duplicate OS names are resolved by the host before entry. Invalid UTF-8 in process inputs is a startup failure on native stderr with exit 70 before main runs. Relative file paths on native CLI roots use the live process working directory; explicitly constructed filesystem services can retain a fixed base.

The native CLI grants its ordinary OS filesystem, networking, and subprocess access. There are no per-function dependency declarations, injected replacements, or manifest permission enforcement. Explicit interface parameters remain useful for substituting source fakes in helpers; applications may also call imported host accessors directly.

## Resources and tests

The host creates synchronized service implementations behind ordinary contract views. The host closes roots after main and its scoped work finish. Applications register acquired files and other resources with `with`; retaining a reference does not prolong their open lifetime. Closing a root stream affects every alias in that execution.

Each source test receives fresh host roots with an empty argument list and its own environment snapshot. Imported accessors work in test bodies. Roots close after test work joins, and closing a root in one test does not close another test's root wrapper. No fake host or API replacement facility is implied by these accessors.

## Exit and shutdown

Normal main results must be 0–125; other results fault. An unhandled root or cleanup fault exits 70 after attempted cleanup and reports primary/secondary diagnostics on host stderr. SIGINT/SIGTERM request cancellation; after joining and cleanup SIGINT exits 130 and SIGTERM exits 143. The first accepted stop reason is retained; a fault during joining/cleanup takes precedence and exits 70. Parent cancellation unwinds main rather than becoming a normal Result.

The `ms run` launcher forwards SIGINT/SIGTERM to the native host and waits for its joined shutdown before reporting that exit status.

Construct application Scheduler services in main with `with`, inside their dependencies' scopes. Shutdown stops admission, joins services, then releases roots. Uncooperative work/reporters can require [host escalation](../../concurrency/runtime.md#host-escalation); the host exposes its watchdog policy. Escalated exit is incomplete cleanup, not conformance success.

Network services register under their construction execution and join before host roots are released. Network owns acquired TCP/UDP/TLS handles and joins them during host-root shutdown. The bounded HTTP and subprocess contracts are in [HTTP](http.md#request-api) and [streams](../data-and-io/streams.md). The filesystem, entropy, wall-clock, and system contracts are in [general-purpose packages](_index.md).

The imported `control()` accessor returns ProcessControl for current-process information and explicit environment, directory, identity, signal, and umask operations. See [process contracts](node-host.md) for their process-wide effects and native limitations.
