# Host operations as module functions

## Summary

- Problem: `filesystem()`, `network()`, `clock()`, `system()`, `control()`, `commands()`, `entropy()`, `terminal()`, `files()` are getters that return a host-handle interface; every call starts with a getter, then a method.
- Change: ambient host operations become functions of their module, as in Node (`fs.readFile`), Python (`os.listdir`, `time.time`) and Go (`os.ReadFile`, `time.Now`). Types remain only for configured or stateful values (a restricted `Network`, `HttpClient`, `Subprocess`). Getters and host-handle interfaces are deleted.
- Decision requested: the per-module table below, and the two open questions.

## Status

Proposal, 2026-10-31, checked at `be04a207`. Chinmay: "having one filesystem(), network() functions feels very weird ... same for rest of the stdlib as well", then "should these be free functions instead? see how the stdlib for node/python/go is setup". Interface-typed default parameters check (`ms check`, scratch project). Skeptic review pending.

## Problem

```
import filesystem from "@std/fs.ms"
import network from "@std/net.ms"
let fs = filesystem()
let text = try fs.read_file("a.txt")
let client = try network().http_client(HttpClientOptions())
```

- The getter adds a line and a name that carry no meaning. Nothing implements `FileSystem`, `Network`, `Clock`, `WallClock`, `System`, `ProcessControl`, `Terminal` or `Files` but the host (`grep 'impl X for'`: none), so the interface is not an abstraction.
- `fs.ms` already mixes both: `basename`, `join` are free functions, `posix()` returns a `PathOperations` interface with the same methods.
- Constants are calls: `math.pi()`, `max_int()`, `process.os_type()`, `end_of_line()`.
- Only `Commands` (`tests/e2e/testdata/stdlib/defaults.ms:12`) and `Entropy` (`tests/conformance/fixtures/e2e/stdlib/random.ms:12`) are implemented by user code, for fakes.

## Design

Rule: an operation on the host is a function in its module; a value that carries configuration or state is a type.

```
import read_file from "@std/fs.ms"
import restrict, http_client from "@std/net.ms"
let text = try read_file("a.txt")
let client = try http_client(HttpClientOptions())
let narrow = try restrict(["example.com"], [], false)   # a Network value
let limited = try narrow.http_client(HttpClientOptions())
```

| Module | Before | After |
| --- | --- | --- |
| `fs` | `filesystem().read_file(p)` | `read_file(p)` and every other `FileSystem` method as a function; `posix()`/`win32()` unchanged |
| `net` | `network().connect(a)` | `connect(a)`, `serve`, `http_client`, `web_socket`, `with_resolver`, `restrict`; `Network` stays an interface only as the value `restrict` and `with_resolver` return |
| `time` | `clock().now()`, `wall_clock().now()` | `monotonic() Instant`, `now() Timestamp` |
| `process` | `commands().run`, `control().…`, `system().…` | `run`, `spawn`, and the `ProcessControl`/`System` methods as functions |
| `io` | `terminal().…`, `files().open(p)` | terminal functions; `open(p)`; `stdin()`, `stdout()`, `stderr()` keep returning the shared stream |
| `random` | `secure_int(entropy(), a, b)` | `secure_int(a, b)`; see Open questions |
| `math`, `process` constants | `pi()`, `os_type()` | values, see Open questions |
| `http`, `log` | `headers()`, `stdout_transport()` | unchanged: constructors of a configured value |
| `crypto`, `json`, `encoding`, `csv`, `string`, collections | already functions or methods on a value | unchanged |

- Each removed method keeps its name and arguments as a function, so migration is mechanical: drop the getter, import the function.
- One spelling per operation (`wiki/stdlib-design`): `FileSystem` and its getter are deleted, not kept beside the functions. `Network` is the exception because a restricted network is a real value.
- The .ms half of each module calls the same `extern fn` natives the interface methods call today.
- Faking: a function that accepts a role takes it as a defaulted parameter, `entropy: Entropy = HostEntropy()`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/{fs,net,time,process,io,random}.ms` | getters and host interfaces become functions | `tests/e2e/testdata/stdlib/*.ms` |
| `crates/ms-lower` `native.rs`, `natiface.rs` | interface-method natives become plain `extern fn`s; coordinate with the "Simplify Rust code structure" thread | `cargo nextest run -p ms-lower` |
| `ms-check` | undefined-name hint for a removed getter | conformance reject case |
| docs, `crates/ms-tooling/data/cheatsheet.md` | examples | `make docs-check` |
| ~2,400 getter calls in `.ms`/`.md` (measured: grep of 11 getter names) | mechanical rewrite | `make verify-full` |

## Alternatives

- Do nothing: the getter noise remains.
- Concrete types built by `FileSystem()`, `Network()` (first draft of this proposal): fixes the spelling but keeps an object whose only state is "the host"; none of Node, Python or Go does this.
- Module functions plus kept interfaces everywhere: doubles the surface and breaks one spelling per operation.

## Stages

1. `fs`, `time`, `random`: functions, call-site rewrite. `make verify`.
2. `process`, `io`: functions. `make verify`.
3. `net`, with `restrict` as a function. `make verify`.
4. Constants, only if approved. `make verify-full`.

## Open questions

- `Commands` and `Entropy` fakes: recommend defaulted interface parameters with `HostCommands()`/`HostEntropy()` types, so `run(...)` and `secure_int(...)` work without them.
- Constants (`math.pi`, `os_type`): need an exported-constant form, which does not exist; a small language change. Recommend yes, as its own stage.
