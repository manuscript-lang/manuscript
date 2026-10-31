# Host operations as module functions

## Summary

- Problem: `filesystem()`, `network()`, `clock()`, `system()`, `control()`, `commands()`, `entropy()`, `terminal()`, `files()` are getters that return a host-handle interface; every call starts with a getter, then a method.
- Change: ambient host operations become functions of their module, as in Node (`fs.readFile`), Python (`os.listdir`, `time.time`) and Go (`os.ReadFile`, `time.Now`). Types remain only for configured or stateful values (a restricted `Network`, `HttpClient`, `Subprocess`). Getters and host-handle interfaces are deleted.
- Decision: approved.

## Status

Approved, 2026-10-31, checked at `be04a207`; skeptic review applied. Chinmay: "having one filesystem(), network() functions feels very weird ... same for rest of the stdlib as well", then "should these be free functions instead? see how the stdlib for node/python/go is setup". Interface-typed default parameters check (`ms check`, scratch project). Approved by Chinmay 2026-10-31: plain free functions, no injectable `Commands`/`Entropy` interfaces, constants become values.

## Problem

```
import filesystem from "@std/fs.ms"
import network from "@std/net.ms"
let fs = filesystem()
let text = try fs.read_file("a.txt")
let client = try network().http_client(HttpClientOptions())
```

- The getter adds a line and a name that carry no meaning. Only `FileSystem` (conformance snippet `testfilesystemimplementationdefaultsoverrideonlyco-3.ms`, `tests/e2e/testdata/stdlib/fs-defaults.ms`, which exercises interface default methods) and `Commands`/`Entropy` are implemented by user code; no user code implements `Network`, `Clock`, `WallClock`, `System`, `ProcessControl`, `Terminal` or `Files`. The `FileSystem` fixtures move to a source type in the test that exercises interface defaults.
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
- No injection: `run`, `spawn` and `secure_int` take no `Commands`/`Entropy` parameter; the `Commands` and `Entropy` interfaces are deleted and their fake-based fixtures are rewritten or removed with owner approval of each.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/{fs,net,time,process,io,random}.ms` | getters and host interfaces become functions | `tests/e2e/testdata/stdlib/*.ms` |
| `crates/ms-lower` `native.rs`, `natiface.rs` | interface-method natives become plain `extern fn`s; coordinate with the "Simplify Rust code structure" thread | `cargo nextest run -p ms-lower` |
| `ms-check` | undefined-name hint for a removed getter | conformance reject case |
| docs, `crates/ms-tooling/data/cheatsheet.md` | examples | `make docs-check` |
| ~1,050 getter calls in `.ms`/`.md` (measured: grep of the 10 getter names; also references in `ms-check`, `ms-syntax`, `ms-cli`, `ms-std-time`, `ms-rt/start.rs`) | mechanical rewrite | `make verify-full` |

## Net, collisions, injection

- `net`: free functions are the same operations on the process-wide host network. `restrict` and `with_resolver` return a `Network` value that keeps every method and `close()`, with the documented rule that closing a parent closes its children. The host network has no `close`; programs that need cancellation scope derive a network with `restrict` (an unrestricted call is `restrict([], [], true)` style, exact signature set in stage 3). Net functions: `connect`, `connect_tls`, `connect_unix`, `listen`, `listen_tls`, `listen_unix`, `bind_datagram`, `lookup`, `request`, `request_bytes`, `serve`, `serve_connections`, `http_client`, `web_socket`. DNS `Network.resolve` keeps its method name and does not get a free `resolve`, which `net.ms` already uses for URLs.
- `fetch.fetcher(options, net: Network = network())` becomes `net: Network? = none`, using the host network when `none`. `log.file_transport` calls `fs` functions directly.
- Collisions: `System.info` and `ProcessControl.info` keep distinct names (`system_info`, `process_info`); `process.constants`/`fs.constants` stay module-qualified; `ProcessControl.monotonic_time` is removed in favour of `time.monotonic()`. Callers alias on import (`import open as fs_open`); `ms-check` already supports this.

## Alternatives

- Do nothing: the getter noise remains.
- Concrete types built by `FileSystem()`, `Network()` (first draft of this proposal): fixes the spelling but keeps an object whose only state is "the host"; none of Node, Python or Go does this.
- Module functions plus kept interfaces everywhere: doubles the surface and breaks one spelling per operation.

## Stages

1. `fs`, `time`, `random`: functions, call-site rewrite. `make verify`.
2. `process`, `io`: functions. `make verify`.
3. `net`, with `restrict` as a function. `make verify`.
4. Constants as exported values (small language change). `make verify-full`.
5. Private helpers with a leading `var` receiver become `var fn` methods on that type (`csv` `Reader`: `next_quote`, `next_delimiter`, `next_line`, `read_record`; the same shape in `toml`, `sse`, `jsonstream`, `bytes`, `encoding`, `cli`). Behaviour-preserving; `ms check` accepts `impl Reader:` with `var fn` (scratch project). Own PR. `make verify`.
6. Group modules into packages under `stdlib/<package>/`, as `stdlib/test/` already does; imports become `@std/net/http.ms`. No old-path aliases (the stdlib ships with the compiler). One mechanical PR: `git mv`, import rewrite, `crates/ms-check/src/stdlib.rs` list, docs, fixtures; recorded expectations that embed paths are re-recorded. Proposed packages:

| Package | Modules |
| --- | --- |
| `net/` | `net`, `http`, `fetch`, `router`, `sse` |
| `io/` | `io`, `streams`, `archive`, `channels` |
| `os/` | `fs`, `process`, `processes`, `time`, `random` |
| `data/` | `json`, `jsonstream`, `csv`, `toml`, `yaml`, `encoding`, `html`, `semver` |
| `collections/` | `collections`, `deque`, `queue`, `sorted`, `bitset`, `iterable`, `ordering` |
| `concurrency/` | `tasks`, `sync`, `shared`, `workers` |
| `math/` | `math`, `decimal` |
| `test/` | `test`, `bench` (existing `test/` contents stay) |
| top level | `core`, `string`, `bytes`, `crypto`, `log`, `cli` |

