# Host capabilities as types, not getter functions

## Summary

- Problem: `filesystem()`, `network()`, `clock()`, `system()`, `control()`, `commands()`, `entropy()`, `terminal()`, `files()` are zero-argument functions that return an interface. Callers write a function call to get a thing whose name is a noun.
- Change: each host capability is a type constructed like any other (`FileSystem()`, `Network()`), with its operations as methods. No new syntax; the getter is deleted, not aliased.
- Decision requested: the naming rule below, and whether to keep interfaces for the two roles users fake in tests.

## Status

Proposal, 2026-10-31, checked at `be04a207`. Examples type-check against stub `type FileSystem`/`type Network` with a defaulted `handle: Int` field and `restrict` (`ms check`). Skeptic review pending. Chinmay: "having one filesystem(), network() functions feels very weird, can we do it properly in a way that makes sense? same for rest of the stdlib as well". Supersedes nothing; #2119 (import allow list) is separate.

## Problem

```
import filesystem from "@std/fs.ms"
import network from "@std/net.ms"
let fs = filesystem()                  # a verb-less call that returns a handle
let client = try network().http_client(HttpClientOptions())
```

- Getters are the only constructor spelling in the stdlib that is not a type: `TaskGroup[T]()`, `Set(list)`, `HttpClientOptions()` all construct by type name (`stdlib/tasks.ms:364`).
- They hide the cost: `network()` and `filesystem()` read like constants, `Network.restrict(...)` and `with_resolver` return derived handles with state.
- Survey of the shape (`grep '^export fn name() Type' stdlib/*.ms`):

| Getter | Returns | Kind |
| --- | --- | --- |
| `fs.filesystem()` | `FileSystem` interface | host handle, never implemented by users |
| `net.network()` | `Network` interface | host handle, derives restricted children |
| `time.clock()`, `time.wall_clock()` | `Clock`, `WallClock` | host handle |
| `process.system()`, `control()` | `System`, `ProcessControl` | host handle |
| `process.commands()` | `Commands` | host handle; users fake it (`tests/e2e/testdata/stdlib/defaults.ms:12`) |
| `random.entropy()` | `Entropy` | host handle; users fake it (`tests/conformance/fixtures/e2e/stdlib/random.ms:12`) |
| `io.terminal()`, `io.files()` | `Terminal`, `Files` | host handle |
| `io.stdin()`, `stdout()`, `stderr()` | `ReadStream`, `WriteStream` | process-wide streams |
| `process.endianness()`, `os_type()`, `end_of_line()`, `dev_null()`, `math.pi()`, `max_int()` | `String`/`Float`/`Int` | constants spelled as calls |

## Design

One rule: a host capability is a type named for the thing, built by `Name()`; operations are its methods.

```
import FileSystem from "@std/fs.ms"
import Network from "@std/net.ms"
let fs = FileSystem()
let client = try Network().http_client(HttpClientOptions())
let narrow = try Network().restrict(["example.com"], [], false)
```

- Types with no user implementers become concrete types whose only field is a defaulted native handle, the pattern `TaskGroup` already uses (`scope: Int = new_scope(...)`): `FileSystem`, `Network`, `Clock`, `WallClock`, `System`, `ProcessControl`, `Terminal`, `Files`. Methods are unchanged.
- Roles users already implement for tests stay interfaces: `Commands`, `Entropy`. Their host implementation is a type `HostCommands()` / `HostEntropy()`; APIs that accept a role keep the interface parameter.
- `stdin()`, `stdout()`, `stderr()` become `Stdin()`, `Stdout()`, `Stderr()` types implementing `ReadStream`/`WriteStream`. Each wraps the one process stream; two values share it, as today.
- Constants become values, not calls: `math.pi`, `math.max_int`, `process.os_type`, `process.end_of_line`. Needs an exported-constant form; none exists today (`grep '^export (let|const)' stdlib` is empty), so this part is a language change. It is a separate stage and may be dropped.
- Derived handles (`restrict`, `with_resolver`) are unchanged: they already are methods returning `Network`.
- No alias period: the repository ships with its stdlib, every call site is in-tree, and "one spelling per operation" is recorded in `wiki/stdlib-design`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/{fs,net,time,process,io,random}.ms` | getters deleted, types with native-handle fields, `extern fn` returns the handle | `tests/e2e/testdata/stdlib/*.ms` |
| `crates/ms-lower` `native.rs`, `natiface.rs` | host interface natives return the handle value; coordinate with the "Simplify Rust code structure" thread, which is moving this knowledge into `.ms` | `cargo nextest run -p ms-lower` |
| `ms-check` | undefined-name hint naming the type that replaced a removed getter | conformance reject case |
| `documentation/`, `crates/ms-tooling/data/cheatsheet.md`, `ms guide` | examples | `make docs-check` |
| ~2,400 getter calls in `.ms` and `.md` files (measured: grep of the 11 getter names) | mechanical rewrite | `make verify-full` |

## Alternatives

- Do nothing: keeps one odd spelling; the cost is learning, not correctness.
- Module-level functions with an ambient capability (`fs.read_file(path)`): shortest to write, but removes `restrict` and fake-ability, which the capability design exists for.
- Keep interfaces and add a constructor-like `Host` prefix everywhere (`HostFileSystem()`): uniform, but longer for types nobody fakes.
- Keep getters, rename to `get_filesystem()`: still a function returning a noun.

## Stages

1. `fs`, `net`: types and rewrite of call sites. `make verify`.
2. `time`, `process`, `io`, `random`. `make verify`.
3. Constants (only if a constant form is approved). `make verify-full`.

## Open questions

- Should `Commands` and `Entropy` stay interfaces with `Host*` types, or become concrete too and lose test fakes? Recommend keeping interfaces: tests rely on them.
- Add an exported-constant form for `math.pi` and similar? Recommend yes, as a small separate language change.
