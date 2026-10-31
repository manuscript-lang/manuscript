# Integrating external software: child process options and C libraries

## Summary

- Problem: a program can run another program but not in another directory or with a chosen environment, and it cannot call a C library such as libuv: `extern fn` takes only `Int`, `Float`, `Bool` and borrowed `String`, so every pointer, `int`, struct and callback needs a hand-written C shim against `ms_abi.h`.
- Change, processes: `Commands.run` and `Commands.spawn` gain `directory: String?` and `environment: Map[String, String]?`; `Subprocess` gains `pid()`. No new type.
- Change, C libraries: user `extern fn` accepts the sized numeric types and a new `Pointer` scalar; a new `@std/native.ms` adds `Pointer` reads and writes, an owned `Memory` block, `callback(f)` (a C function pointer for a top-level `fn` or an extern), a way to hand a `Shared[T]` to C as `void *` user data, and `on_stop` so a stop request can wake a loop blocked in C. All of it is ordinary Manuscript over about a dozen small runtime primitives. Linking stays `--link`.
- Cost: one scalar type, one checker rule (`callback` names a top-level `fn` or an extern), a C-ABI entry per callback function, extension attributes on narrow integer arguments, one stdlib module. No new syntax, keyword or manifest table.
- Decision requested: approve the design and the four open questions (whether `Pointer` is a new type, `Pointer` method names, cancellation inside callbacks, and how bindings declare their native inputs).

## Status

- Proposal, 2026-10-31, checked against `d4a94aa9`. Nothing implemented.
- Request (Chinmay, 2026-10-31): "design a process /ffi to enable integrating with other external software"; "use case could be to integrate with libuv for instance". libuv is the worked example and the acceptance test.
- Standing direction: Manuscript first (stdlib `.ms`, Rust only for small general primitives); Linux, macOS and Windows parity; native identity is the declared name (`bindings.json` removed, "the Manuscript name is the symbol, no `as`"); one `Closeable` whose `close()` returns `Unit!`; `T!E` result shorthand.
- Builds on: `extern fn` (#1136, #1138; `documentation/core-language/functions/native-functions.md`), sized and unsigned numeric types (`proposals/sized-numeric-types.md`, `proposals/unsigned-integer-types.md`), `Shared[T]` (`stdlib/shared.ms`), workers (`proposals/worker-threads.md`), the bundled linker (`proposals/bundled-linker.md`), and the earlier extern review, whose "narrow v1" (scalars and borrowed strings) this extends.
- Prior open idea, "generic extern fn and a callback marker": resolved below with no new language feature (see Design, "Generic externs and kept callbacks").
- Skeptical review, 2026-10-31 (independent subagent, against source): build with changes. Folded in: the isolate check uses the isolate registration (`msrt_isolate_hdr` never returns null, `crates/ms-rt/src/fault.rs:100`); `on_stop` added because a loop blocked in C never polls cancellation; `Memory.release` is a `var fn` that empties the block, like `SharedGuard`; a callback fault is a barrier, not a guard; pins are generation-tagged handles, so a double take faults; the `[link]` table is dropped (the manifest reader takes only string values in `[project]`/`[aliases]`, and the program's manifest, not the binding's, would carry it); process options use `Command::current_dir`/`env_clear` and define directory, PATH and error behavior so all three platforms agree; the example closes the handle through the loop when `uv_timer_start` fails. Part 1 is independent of Part 2 and ships as its own stage.

## Problem

- Verified: a binding cannot declare libuv's own signatures today.

  ```text
  extern fn uv_timer_init(loop: Int, timer: Int) Int32
  a.ms:1:48: type: extern result has type Int32, which cannot cross the native boundary; return Int, Float, Bool, String, Unit, or a Result of them
  ```

  The argument list is `Int`, `Float`, `Bool`, `String` (`crates/ms-check/src/checker.rs:1268`). `Int32` and `UInt64` now exist in the language but cannot cross.
- Verified: there is no way to get a C function pointer for a Manuscript function. libuv reports every event through one (`uv_timer_cb`, `uv_connection_cb`, `uv_read_cb`, `uv_close_cb`).
- Verified: there is no memory a C library may keep. `Bytes` and `List` move bitwise and reallocate (ABI.md section 4), so their address is not stable; libuv keeps a `uv_tcp_t *` until its close callback runs.
- Verified: native inputs come only from `--link <file>` on each command (`crates/ms-cli/src/invocation.rs:36`). That is enough for one program; how a reusable binding declares its archives is left open (Open question 4).
- Verified: `Commands.run`/`spawn` (`stdlib/process.ms:65-80`) take no working directory and no environment. A program must `change_directory` for the whole process, which races with tasks, and cannot clear a secret from a child's environment. `Subprocess` has no `pid()`.
- Consequence: integrating libuv, SQLite, libcurl, zlib or a vendor SDK today means writing and compiling C for every function that touches a pointer. That is the opposite of Manuscript first, and an agent writing the binding needs two languages and a C toolchain.
- Non-goals:
  - Structs passed or returned by value, variadic functions (`printf`), C `long` (32-bit on Windows, 64-bit elsewhere), and bitfields. These keep using a C shim.
  - Callbacks from threads Manuscript does not run (libuv's `uv_queue_work` work callback). Use a worker isolate instead.
  - Dynamic loading (`dlopen`, `LoadLibrary`). Linux executables are static musl without `dlopen` (`proposals/bundled-linker.md`), so it cannot be at parity.
  - Generating bindings from C headers. A later tool can emit the `.ms` this design defines.
  - Exposing Manuscript functions to C programs that link a Manuscript library.

## Design

The rule: **a C library is bound in Manuscript.** A binding module declares the library's functions as `extern fn` with their real C types, keeps them private, and exports ordinary Manuscript types and functions over them. `@std/native.ms` supplies the few things Manuscript cannot express itself: an address, memory at a stable address, a function pointer, and a reference that C can hold.

### Part 1: child process options

```manuscript
import commands, control from "@std/process.ms"

export fn status(repo: String) String!Error:
    var env = try control().environment()
    env["GIT_PAGER"] = "cat"
    let out = try commands().run("git", ["status", "--short"], directory: repo, environment: env)
    return ok(out.stdout.decode_utf8().get(""))
```

- `directory: String?` on `run` and `spawn`: the child starts there; none keeps the parent's. Checked before starting: a missing or non-directory path is `CommandError.Unavailable` on every platform (Windows would otherwise report `ERROR_DIRECTORY` as `Failed`).
- `environment: Map[String, String]?`: when given it is the child's whole environment; none inherits the parent's. One rule, no merge semantics: to add a variable, copy `control().environment()` and change it, as above. A key that is empty or contains `=` or NUL is `InvalidInput`. Nothing is added silently; the doc comment warns that many Windows programs need `SystemRoot`.
- Program lookup is done by `ms-std-process`, not left to the platform, so it is the same everywhere: a `program` containing a path separator is resolved against the parent's working directory (not `directory`); otherwise it is searched on the `PATH` the child will see (the given `environment`'s, else the parent's). No `PATH` and no match is `Unavailable`.
- `Subprocess.pid() Int`: the operating system's process id, for logs and for `control().send_signal`.
- Rust: `crates/ms-std-process/src/spawn.rs` (`start`, called by `spawn_with` in `command.rs:289`) builds a `std::process::Command`; it gains `current_dir`, `env_clear` plus `envs`, and the lookup above. The existing extra variables for `ProcessGroup` are added after the given environment.
- Unchanged: `Stdio`, streams, timeouts, process-group kill on close and cancellation, `ProcessGroup`.

### Part 2: C libraries

#### Types that cross

| Manuscript | C |
| --- | --- |
| `Int8`, `Int16`, `Int32`, `Int64`/`Int` | `int8_t` ... `int64_t` (`int` is `Int32`) |
| `UInt8`, `UInt16`, `UInt32`, `UInt64` | `uint8_t` ... `uint64_t` (`size_t` and `uintptr_t` are `UInt64`) |
| `Float32`, `Float`/`Float64` | `float`, `double` |
| `Bool` | `bool` (`_Bool`, one byte) |
| `Pointer` | any `T *`, including function pointers and `void *` |
| `Unit` result | `void` |
| `String` argument, `String` and `Result` results | unchanged: the existing `ms_str` conventions for shims written against `ms_abi.h` |

- Arguments are passed in registers or on the stack exactly as the platform C ABI says (System V on Linux and macOS x86_64, AAPCS64 on arm64, Microsoft x64 on Windows). Code generation adds sign or zero extension to narrow arguments and results; today only `I8` gets `uext` (`crates/ms-clif/src/cg.rs:14`), and Apple arm64 requires the caller to extend.
- An extern still cannot be generic, take defaults or `var` parameters, or be a method (`native-functions.md`).
- Everything else is rejected with the existing diagnostic, whose list of types grows.

#### `@std/native.ms`

```manuscript
# A machine address. Copying it copies the address; it owns nothing.
export type Pointer          # a scalar, like UInt64 (see Open questions)

impl Pointer:
    fn is_null() Bool
    fn offset(bytes: Int) Pointer
    # Reads or writes a T at `offset` bytes. T is a numeric type, Bool or Pointer.
    # Unchecked: a wrong address is undefined behavior, like in C.
    fn read[T: NativeValue](offset: Int = 0) T
    fn write[T: NativeValue](value: T, offset: Int = 0) Unit
    fn read_bytes(length: Int, offset: Int = 0) Bytes
    fn c_string_length() Int                   # strlen
    fn to_shared[T]() Shared[T]                # see "Handing state to C"
    fn take_shared[T]() Shared[T]

export fn null_pointer() Pointer

# Memory at a stable address from the C allocator, zeroed, freed on close.
export type Memory:
    pointer: Pointer
    size: Int

impl Memory:
    fn read[T: NativeValue](offset: Int = 0) T     # faults when offset + size of T > size
    fn write[T: NativeValue](value: T, offset: Int = 0) Unit
    var fn release() Pointer                       # C now owns it: the block becomes empty and closing it frees nothing

impl Closeable for Memory                          # close frees; ok(unit)

export fn allocate(size: Int) Memory
export fn c_string(text: String) Memory            # UTF-8 bytes plus NUL
export fn free(pointer: Pointer) Unit              # C free(); also frees what a library malloc'd

export fn to_pointer[T](box: Shared[T]) Pointer
export fn callback[F](function: F) Pointer         # F names a top-level fn or an extern; checker rule below

# Calls `function(argument)` when a stop is requested for this isolate; closing the hook removes it.
export fn on_stop(function: Pointer, argument: Pointer) StopHook
export type StopHook                                # Closeable
```

- `Pointer` is unchecked by nature. The rest of the language stays memory safe; `import ... from "@std/native.ms"` is the visible boundary, and `ms review` lists modules that import it as native boundaries (inspection already treats extern calls as external, `wiki/tooling-and-docs/project-review-must-keep-library-internals-behind-their-boun.md`).
- `Memory` is the safe way to own C memory: reads and writes are bounds-checked, close frees it at scope end, and `release()` is the one explicit hand-off to C. `release` follows `SharedGuard.held` in `stdlib/sync.ms`: it returns the pointer and leaves the block empty, so the binding must be `var` and its scope-end close frees nothing. It comes from libc `malloc` (musl on Linux, the UCRT on Windows, libSystem on macOS) and never from the runtime's per-isolate arena (`crates/ms-rt/src/glue/pool.rs` explains why arena blocks must not be freed by another thread), so C may `free` it and Manuscript may `free` what C allocated.
- `NativeValue` is a marker interface (like `Copy`) implemented by the numeric types, `Bool` and `Pointer`; it is how `read[Int32]` is limited to scalars without a method per type.
- Implemented in `.ms` over runtime primitives: `msrt_native_alloc`, `msrt_native_free`, `msrt_native_load_<n>`/`store_<n>` (1, 2, 4, 8 bytes), `msrt_native_strlen`, `msrt_native_copy_bytes`, `msrt_native_pin`, `msrt_native_pinned`, `msrt_native_unpin`, `msrt_native_on_stop`, `msrt_native_stop_hook_close`. Bounds checks, `c_string`, string decoding and `Memory` are Manuscript. Hot loads can become intrinsics later, after a measurement.

#### Callbacks

```manuscript
fn on_tick(timer: Pointer) Unit:       # a top-level fn whose types all cross
    ...

uv_timer_start(timer, callback(on_tick), 10, 10)
```

- `callback(f)` returns a C function pointer with `f`'s signature. The compiler emits one C-ABI entry per function named by a `callback` call; calling it twice gives the same pointer. Functions already use the platform C calling convention (`make_signature` in `crates/ms-clif/src/cg.rs`), so the entry is a thin wrapper, and the LLVM backend translates the same IR. For an `extern fn`, `callback` is the symbol's address with no entry, which is how `on_stop` gets `uv_async_send`.
- Checker rule, the same shape as worker and process entries (`crates/ms-check/src/calls.rs:455`, `:547`): the argument must name a top-level, non-generic `fn` or an `extern fn` whose parameters and result are `NativeValue` types or a `Unit` result. Proposed diagnostic: `a native callback must be the name of a top-level fn; C keeps only a code address, so a closure's captured values cannot come with it. Pass state as a Pointer from to_pointer instead`.
- No captures, so no closure is kept alive and no ownership marker is needed: state travels through the library's `void *` user-data slot.
- Where it runs: on the thread that called into C, which must be a Manuscript isolate (the main isolate or a worker) currently inside an extern call. The entry checks the thread's isolate registration (`isolate::CURRENT`, `crates/ms-rt/src/isolate.rs:51`), not `msrt_isolate_hdr()`, which falls back to a thread-local root header and never fails (`fault.rs:100`). A call from any other thread, or from a stop hook, writes `native callback ran on a thread Manuscript does not run; call this library from a worker instead` and exits 67. The check comes before any generated code that masks the stack pointer to find its task header (ABI.md section 7).
- Faults: the entry is a barrier. A fault inside a callback hides every enclosing guard and behaves as an unguarded fault: all cleanups run (including the outer ones, such as process-group kills), the report is written, and the process exits 67. It never jumps through C frames, because C has no landing pads and the library's state would be left half-updated. In a worker this ends the whole process, not just the worker; a binding that must survive a fault keeps its callbacks small and returns errors as values.
- Cancellation: the body runs shielded (the existing cleanup shield), so it finishes and returns a value to C. The request is seen at the first poll after the outer `extern` call returns. A loop blocked in C never returns by itself, so `on_stop` (below) is how a binding makes it return. The 30 s forced exit still bounds a callback that never returns.
- A callback may park (wait on a channel, sleep): tasks are stackful, so the C frames below it stay intact. Another task may then call into the same library; whether that is safe is the library's rule, and the binding documents it.
- Fault traces: frames are walked by frame pointer; C code built without them truncates the trace at the C frame. Documented, not fixed.

#### Handing state to C

- `to_pointer(box)` gives C one reference to a `Shared[T]` and returns a handle, not an address: an index into a per-isolate pin table plus a generation, packed into the pointer's bits. The entry records the box and `T`'s type descriptor (descriptors are interned per type, `desc_ids` in `crates/ms-clif/src/cg.rs`; generic bundled externs already receive them, ABI.md section 8).
- `pointer.to_shared[T]()` returns a new reference and leaves C's in place (for callbacks that run many times). `pointer.take_shared[T]()` returns C's reference to Manuscript and retires the entry (for the last callback, typically close).
- Both fault, with no memory read outside the table, when the handle belongs to another isolate or an earlier occupant of its slot (the generation differs; `Shared` counts are not atomic), was already taken, or was made for another `T`. A wrong cast or a double take is a fault, never memory corruption.
- A pin that is never taken leaks one reference, like a `Shared` cycle (ABI.md section 2).

#### Calls that block

- An extern call runs to completion on the calling isolate's thread. A call that blocks, such as `uv_run` or `sqlite3_step`, stalls every task on that isolate, and cancellation waits for it to return.
- The answer is the existing one: run the library in a worker (`WorkerGroup.spawn`), and talk to it over the worker's channel. No blocking-call marker or thread hand-off is added, because callbacks must run on the isolate that called in.
- For libuv specifically, the main isolate wakes a loop running in a worker with `uv_async_send`, the one libuv function that is safe from any thread.

#### Stopping a loop blocked in C

- A stop request (SIGINT, SIGTERM, `Worker.cancel`, a task group's cancellation of the worker) only sets a flag that Manuscript code polls (ABI.md section 7). Code blocked in `uv_run` never polls, so without help every Ctrl-C ends in the 30 s forced exit.
- `on_stop(function, argument)` registers a C function that the runtime calls as `function(argument)` at the moment a stop is requested for this isolate, from the requesting context: the signal handler for signals, the cancelling thread for `Worker.cancel`. It must therefore be async-signal-safe and thread-safe; `uv_async_send` is documented as both. Closing the `StopHook` unregisters it.
- libuv pattern: an `uv_async_t` whose callback calls `uv_stop(loop)`, registered with `on_stop(callback(uv_async_send), wake)`. `uv_run` returns, the extern call returns, and the next poll unwinds with the usual cleanups.
- A Manuscript `callback` pointer passed as `function` faults when called (the entry's thread check), since a stop hook runs outside the isolate.

#### Linking

- Unchanged: `--link <file>` (repeatable) names objects and static archives. Archives must match the bundled toolchain: musl on Linux, mingw (`gnullvm`, UCRT) on Windows (`proposals/bundled-linker.md`). A Windows archive built against `msvcrt.dll` would `free` from another heap.
- Windows: the bundle embeds a fixed set of import libraries (`crates/ms-clif/src/link/lld.rs:240`); libuv also needs `iphlpapi`, `psapi` and `ole32`. Stage 4 adds those three from the same llvm-mingw release; a general way to name system libraries is Open question 4.
- macOS: undefined symbols bind to libSystem unless they start with `_Sec` or `_CF` (`crates/ms-clif/src/link/macos_stubs.rs:32`). libuv needs nothing else; a library using another framework (IOKit, SystemConfiguration) is not supported yet and the documentation says so.
- The documentation gives the libuv `cmake` line per platform.
- libuv installs `SIGCHLD` handling for `uv_spawn` and `SIGINT` handling for `uv_signal_t`; the documentation says to use `@std/process.ms` for child processes and signals instead, so the runtime's handlers stay in charge.

#### Worked example: a libuv timer

Checked with `ms check` against stubs (externs written as placeholder `fn`s, since today's checker rejects their types; `@std/native.ms` stubbed as a local module).

```manuscript
import Pointer, Memory, allocate, callback, free, null_pointer, to_pointer from "@std/native.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"

extern fn uv_default_loop() Pointer
extern fn uv_handle_size(kind: Int32) UInt64
extern fn uv_timer_init(loop: Pointer, timer: Pointer) Int32
extern fn uv_timer_start(timer: Pointer, on_tick: Pointer, timeout: UInt64, repeat: UInt64) Int32
extern fn uv_handle_set_data(handle: Pointer, data: Pointer) Unit
extern fn uv_handle_get_data(handle: Pointer) Pointer
extern fn uv_close(handle: Pointer, on_close: Pointer) Unit
extern fn uv_run(loop: Pointer, mode: Int32) Int32
extern fn uv_strerror(code: Int32) Pointer

let UV_TIMER: Int32 = 13
let UV_RUN_DEFAULT: Int32 = 0

# A failed libuv call: its negative status and libuv's description.
export type UvError:
    case Failed(code: Int32, message: String)

impl Error for UvError:
    fn message() String:
        match self:
            Failed(code, message): return "libuv error {code}: {message}"

fn check(status: Int32) Unit!UvError:
    if status >= 0:
        return ok(unit)
    let text = uv_strerror(status)
    let bytes = text.read_bytes(text.c_string_length())
    return error(UvError.Failed(status, bytes.decode_utf8().get("?")))

# Counts ticks; the timer stops itself after `limit`.
export type Ticks:
    count: Int
    limit: Int

# Runs on the loop's thread each time the timer fires.
fn on_tick(timer: Pointer) Unit:
    let state = uv_handle_get_data(timer).to_shared[Ticks]()
    var ticks = lock(state)
    ticks.value.count += 1
    if ticks.value.count == ticks.value.limit:
        uv_close(timer, callback(on_closed))

# libuv is done with the handle: take back the state reference and free the memory.
fn on_closed(handle: Pointer) Unit:
    let _state = uv_handle_get_data(handle).take_shared[Ticks]()
    free(handle)

# Fires every `every_ms` until `limit` ticks, then returns the final count.
export fn count_ticks(limit: Int, every_ms: UInt64) Int!UvError:
    let loop = uv_default_loop()
    let state = share(Ticks(count: 0, limit: limit))
    var memory = allocate(uv_handle_size(UV_TIMER).to_int().get(0))
    try check(uv_timer_init(loop, memory.pointer))
    # The loop now lists the handle, so only on_closed may free it.
    let timer = memory.release()
    uv_handle_set_data(timer, to_pointer(state))
    let started = check(uv_timer_start(timer, callback(on_tick), every_ms, every_ms))
    if started.is_error():
        # Close through the loop so on_closed frees the handle and the pin.
        uv_close(timer, callback(on_closed))
        try check(uv_run(loop, UV_RUN_DEFAULT))
        return error(started.err())
    try check(uv_run(loop, UV_RUN_DEFAULT))
    return ok(state.get().count)
```

- `uv_handle_set_data`/`get_data` (libuv 1.19+) avoid hard-coding the `data` field offset. Where a layout must be written by hand (`uv_buf_t` is `{base, len}` on Unix and `{ULONG len, base}` on Windows), the binding branches on `os_type()`; parity of the binding is the binding's job, parity of the mechanism is ours.
- If `uv_timer_init` fails, `memory` is still owned and its scope end frees it. Once init succeeds the loop lists the handle, so it is released at once and every later path, including a failed `uv_timer_start`, ends in `uv_close` and `on_closed`.
- The example uses `uv_default_loop()` for brevity; in a worker, a binding allocates its own loop with `uv_loop_init` on `Memory`, since the default loop is one per process.
- A TCP echo server adds `uv_tcp_t`, `uv_buf_t` and the read and write callbacks with the same tools; with a worker-hosted loop and `on_stop` it is the stage 4 fixture.

```text
 Manuscript task stack                          C (libuv)
 count_ticks ── extern call ─────────────────▶ uv_run
                                                 │ timer fires
 on_tick entry (isolate check, shield, guard) ◀──┤ via callback(on_tick)
   to_shared → lock → count += 1                 │
   ── return to C ─────────────────────────────▶ │
 on_closed entry ◀───────────────────────────────┤ uv_close callback
   take_shared, free(handle) ──────────────────▶ │
 count_ticks ◀─────────────────────────────────── uv_run returns
```

### Generic externs and kept callbacks

- Generic `extern fn` already works in bundled modules: `msrt_list_distinct[T]`, `msrt_json_parse[T]`, `msrt_obj_share[T]` pass one descriptor per type parameter (ABI.md section 8). User externs stay non-generic, because a C function cannot take a Manuscript descriptor. Nothing to add.
- The callback marker was meant to replace `KEPT_CALLBACKS` (`crates/ms-check/src/stdlib.rs:94`), the three bundled externs that store a closure. User callbacks never pass a closure (a `callback` pointer captures nothing), so user FFI does not need the marker, and three internal entries do not justify syntax. Recommendation: keep the list.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/process.ms`, `crates/ms-std-process` | `directory`, `environment`, `pid()`; program lookup in Rust so it matches on all three platforms | `tests/e2e/testdata/stdlib/process.ms` cases: temp directory, missing directory is `Unavailable`, replaced environment and its `PATH`, relative program path, pid matches the child's report |
| `stdlib/native.ms` (new) | `Pointer` methods, `Memory`, `allocate`, `c_string`, `free`, `to_pointer`, `callback`, `on_stop`, `StopHook`, `NativeValue` | new stdlib fixture with a C helper archive (`tests/e2e/testdata/native/`) |
| `stdlib/intrinsics.ms` | `Pointer` scalar and its `NativeValue` impls | checker tests |
| `crates/ms-rt` | `msrt_native_*` primitives (alloc, free, loads, stores, strlen, copy, pin table, stop hooks); callback entry helper (isolate registration check, shield, fault barrier); stop hooks called from the signal handler and `msrt_worker_cancel` | unit tests per primitive; foreign-thread, double-take and stop-hook tests |
| `crates/ms-check` | extern argument and result types grow (`checker.rs:1268`); `callback` argument rule; `NativeValue` bound | conformance accept and reject cases with exact diagnostics |
| `crates/ms-lower`, `crates/ms-mir` | `Pointer` lowers as `I64`; `callback(f)` lowers to the address of `f`'s C entry | lowering snapshot |
| `crates/ms-clif` (Cranelift and LLVM) | sign/zero extension for 8/16/32-bit extern arguments and results; one C-ABI entry per callback function, emitted with frame pointers | ABI test calling a C function with every type, both backends, all three platforms |
| `crates/ms-clif/src/link` | Windows: embed `iphlpapi`, `psapi`, `ole32` import libraries (stage 4) | Windows libuv example links |
| `crates/ms-driver` manifest, `--link` | unchanged | |
| `ms-lsp`, formatter, lint | unchanged (no syntax); `ms review` labels `@std/native.ms` importers | review snapshot |
| `documentation/core-language/functions/native-functions.md` | rewritten around binding a C library; libuv build lines per platform | `make docs`, example checks |
| `wiki/language/extern-def-...md` | correct the spelling (`extern fn`, not `extern def`) and the new type list | `make repo-check` |
| `examples/libuv-timer` (new) | the worked example as a project | CI builds it where the archive is fetched |
| parser, grammar, MIR passes, ownership pass | unchanged | |

## Alternatives

- **Do nothing; write C shims.** Works today and is the documented path. It loses on the stated direction: each libuv function needs C, a C compiler, and knowledge of `ms_abi.h`, and the shim cannot call back into Manuscript at all, so libuv is impossible, not just tedious.
- **Smallest version: sized types and `Pointer` in externs only.** Covers zlib-style libraries with no callbacks or kept memory. It does not reach libuv, SQLite's busy handler, or libcurl's write callback. Kept as stage 2 so it ships first.
- **`UInt64` for pointers instead of a `Pointer` type.** No new type, but addresses and sizes mix freely in signatures like `uv_timer_start(Pointer, Pointer, UInt64, UInt64)`, and `read`/`write` would be free functions on integers. Open question 1.
- **Closures as callbacks via trampolines** (libffi closures or generated thunks with an environment slot). Lets C call a capturing closure, but needs executable memory or a thunk pool, an owner for the closure's lifetime, and a kept-callback ownership marker. Every target library already has a user-data pointer, so it buys convenience at real cost.
- **Struct and record layout in the language** (`repr(C)` records). Removes hand-written offsets, but it is a language change with per-platform layout rules; most libraries expose accessors, and libuv's own `uv_handle_get_data` shows the pattern. Revisit with a header-to-binding generator.
- **Run blocking externs on the blocking pool.** Keeps the isolate responsive, but callbacks then run on a pool thread, which has no isolate. Workers already isolate blocking work.
- **Integrate a library's event loop with the runtime poller** (`uv_backend_fd` plus `msrt_task_wait_fd`). Good on Linux and macOS, but libuv on Windows uses IOCP and has no pollable descriptor, so it breaks parity. Deferred; a later general `wait_readable(fd)` can add it for libraries that expose a descriptor on every platform.
- **A `[link]` table in `ms.toml`.** Drafted and dropped after review: the manifest reader takes only string values in `[project]` and `[aliases]` (`crates/ms-driver` manifest), and only the program's nearest manifest is read, so a vendored binding still could not carry its own archives. `--link` covers the libuv stages.
- **Dynamic libraries.** Impossible on static musl Linux; rejected for parity.
- How others do it, where it shaped the choice: Zig and Rust bind C with typed pointers and `extern` declarations in the language itself (chosen shape); Go's cgo needs a C compiler per build (avoided); Python's ctypes and Node's N-API load libraries at run time (impossible here without `dlopen`).

## Staging and verification

Each stage lands green on Linux, macOS and Windows; no platform skips.

1. **Child process options.** `directory`, `environment`, `pid()`. Gate: process fixtures pass on all three platforms.
2. **Scalars and pointers.** Sized types and `Pointer` in externs, extension attributes, `@std/native.ms` without callbacks or pins. Gate: an ABI test archive (C, compiled per target in CI) round-trips every type on both backends.
3. **Callbacks, pins and stop hooks.** `callback`, entry helper, pin table, `on_stop`. Gate: fixture where C calls back into Manuscript; a fault in a callback runs outer cleanups and exits 67 with a trace; a foreign-thread call, a double take and a wrong-type pin each fault; SIGINT to a program blocked in a C loop exits 130 through its hook.
4. **libuv.** `examples/libuv-timer` and a TCP echo server built against libuv 1.x archives fetched by checksum in CI; Windows import libraries added. Gate: both run on all three platforms; a worker-hosted loop is woken by `uv_async_send` and stopped by `Worker.cancel`.
- Go/no-go after stage 3: if the callback entry needs changes to the fault or task machinery beyond the entry helper, stop and report before stage 4.
- Checks per stage: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo nextest run --workspace`, `make verify`, plus `make verify-full` before stage 4 merges.

## Open questions

1. **A `Pointer` type, or `UInt64`?** Recommend `Pointer`: one scalar type keeps addresses out of arithmetic and gives `read`/`write` a receiver.
2. **`Pointer` method names.** `read[T]`/`write[T]` with an explicit type argument (`p.read[Int32](8)`), against one method per type (`read_int32`). Recommend the generic form: eleven fewer names, and the type is visible at the call.
3. **Cancellation inside a callback.** Shielded until the outer extern returns (recommended: C always gets a value back), or delivered inside the callback, which then exits the process from inside C.
4. **How a reusable binding declares its native inputs.** Keep `--link` and document per-platform commands (recommended for now), or design a manifest table once packages exist and a second real binding needs it.
