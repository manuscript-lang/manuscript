# Foreign functions: complete C interop through a native ABI

## Summary

- Problem: a program cannot use a C library such as libuv. `extern fn` crosses only `Int`, `Float`, `Bool` and borrowed `String`. Natives cannot hand Manuscript a resource, call Manuscript back, block without stalling every task, or report error text.
- Approach, taken from how Node (N-API), Python (C API) and Go (cgo) do it: C things stay in C and Manuscript things stay in Manuscript. A binding is a C shim written against a stable, versioned `ms_abi.h`, plus a Manuscript module of typed `extern` declarations.
  - `ms header` generates the C view of those declarations, so the shim and the Manuscript side cannot disagree.
  - `ms cc` is a bundled clang targeting the same musl and mingw runtimes the bundled linker uses, so shims and libraries build the same way on every platform.
- "Complete" means covering what those three systems give native code:
  - every value type crosses;
  - native objects have finalizers and per-isolate state;
  - callbacks run on the same thread;
  - calls can come from any thread, with or without waiting for a result;
  - blocking work runs off the isolate;
  - code can wait on sockets;
  - stop requests reach native code;
  - errors and faults are handled.
  Embedding Manuscript in a C program is a follow-up proposal whose prerequisites are listed below.
- Manuscript code stays memory safe and reads like any other: handles close at scope end, callbacks are closures, failures flow through `try`. There is no `Pointer`, no raw memory, and no new syntax.
- Decision requested: approve the direction and the four open questions.

## Status

- Proposal, 2026-10-31, checked against `d4a94aa9`. Nothing implemented.
- Direction (Chinmay, 2026-10-31):
  - "design a process /ffi to enable integrating with other external software"
  - "use case could be to integrate with libuv for instance"
  - "should we harden the ms abi instead of brining all unsafe behavior into ms?"
  - "ms is supposed to be the language where code will flow like a stream"
  - "keep c things in c and ms things in ms"
  - "no the interop needs to be complete, think critically, how do other languages do this like node or python or go"
- History (git):
  - Draft 1 put pointers and raw memory in Manuscript. Rejected: "keep c things in c".
  - Draft 2 had C call closures directly.
  - Draft 3 only pulled events and had no callbacks. Rejected: "needs to be complete".
  - Draft 4 is this file before its review.
- Skeptical reviews: three independent reviews checked earlier drafts against source, and their findings are folded in. The review of draft 4 asked for revisions, and this text addresses each point:
  - Arguments of a cross-thread call are copied as C views and built on the isolate. The arena forbids building values on a foreign thread (`glue/pool.rs:5`).
  - The toolchain question is answered by `ms cc`.
  - The header exposes accessors, not C structs. Records flatten to leaves and alternatives share payload slots (`crates/ms-clif/src/layout.rs:319`), and layouts are target-independent.
  - Closures handed to C carry their isolate.
  - `ms_blocking` has its own non-unwinding entry, its own lane and its own reap point.
  - Added: synchronous calls from foreign threads, per-isolate data and exit hooks, a no-exceptions rule, and a copy rule for strings.
  - The error message case is dropped in favour of generated error constructors.
  - Containers start with `List` and `Bytes`.
  - The libuv example registers a stop hook.
  - Embedding moves to its own proposal.
- Standing direction:
  - Manuscript first; Rust only for small general primitives.
  - Linux, macOS and Windows parity.
  - The declared name is the symbol (no `as`; `bindings.json` removed).
  - One `Closeable`, whose `close()` returns `Unit!`.
  - `T!E` shorthand.

## Problem

- Verified: the types a user extern may use are fixed (`crates/ms-check/src/checker.rs:1268`):

  ```text
  extern fn uv_timer_init(loop: Int, timer: Int) Int32
  a.ms:1:48: type: extern result has type Int32, which cannot cross the native boundary; return Int, Float, Bool, String, Unit, or a Result of them
  ```

- Verified: other limits in the checker:
  - `extern type` is rejected outside bundled modules (`checker.rs:732`).
  - Error types must be payload-free (`checker.rs:1306`).
  - A user extern cannot take a function value.
- Verified: `ms_abi.h` is 33 lines and declares only `ms_str` and `msrt_string_from_bytes` (`crates/ms-rt-abi/include/ms_abi.h`).
- Verified: a native that blocks stalls every task on its isolate (ABI.md section 7).
- Verified: shims and libraries must be built for musl on Linux and the mingw UCRT on Windows (`proposals/bundled-linker.md`). `ms` bundles a linker but no C compiler.
- Non-goals:
  - Dynamic loading (Open question 3).
  - Generating shims from C headers (a later tool).
  - Embedding Manuscript in C programs (follow-up, see section 10).

## How Node, Python and Go do it

| Capability | Node (N-API) | Python (C API) | Go (cgo) | Manuscript (this proposal) |
| --- | --- | --- | --- | --- |
| Where glue lives | C addon against `node_api.h` | C extension against `Python.h`; `ctypes`/`cffi` for calls without glue | C in the Go file's preamble; cgo reads C headers to derive Go types | C shim against `ms_abi.h` plus `extern fn` in `.ms` |
| ABI stability | `NAPI_VERSION`, stable across Node releases | limited API / `abi3` | none; rebuilt with the program | `MS_ABI_VERSION`, checked at link time |
| Toolchain | node-gyp drives the platform compiler | setuptools drives the platform compiler | the system C compiler (`CC`) | bundled `ms cc` (clang) for the bundled runtimes |
| Values | opaque `napi_value` with create/inspect calls per type | `PyObject *` with functions per type | C types mapped to Go types | every type a signature uses, through generated accessors |
| Zero-copy buffers | external buffers, `napi_create_external_buffer` | buffer protocol | `unsafe.Slice` over C memory | borrowed for the call; native-owned buffers are an `extern type` read by copy (section 1) |
| Native objects | `napi_wrap` with a finalizer | extension types with `tp_dealloc`, capsules | `runtime.SetFinalizer` / `AddCleanup` on a Go wrapper | `extern type` from `ms_object_new(size, drop)` |
| Per-instance state | `napi_set_instance_data`, env cleanup hooks | module state, `m_free` | package variables | `ms_isolate_data`, `ms_on_isolate_exit` |
| Callbacks, same thread | `napi_call_function` | `PyObject_Call` with the GIL held | `//export` functions (`_cgo_export.h`) | generated `ms_call_*` adapters |
| Calls from any thread | `napi_threadsafe_function`, queued | `PyGILState_Ensure`, then call and wait | any C thread calls an exported function and waits | `ms_post_*` (queued) and `ms_call_wait_*` (waits for the result) |
| Blocking work | `napi_create_async_work` | `Py_BEGIN_ALLOW_THREADS` releases the GIL | the runtime hands off the P during a C call | `ms_blocking(work, data)` on a native lane, task parks |
| Foreign event loops | Node is libuv | asyncio by file descriptor | goroutine locked to an OS thread (`LockOSThread`) | loop on its own thread posting with `ms_post_*`, or `ms_wait_socket` |
| Errors | `napi_throw_*`, status per call | exception set, return `NULL` | `errno` as a second result | `Result` built through generated error constructors; `ms_fault` |
| Exceptions crossing | C++ exceptions must not cross | must not cross | panics must not cross | C++ exceptions and `longjmp` must not cross |
| Loading | `dlopen` | `dlopen` | static or dynamic link | static link with `--link` |
| Embedding | embedder API | `Py_Initialize` | `-buildmode=c-archive` | follow-up proposal (section 10) |

What the table settles:

- All three keep unsafe code in C behind a stable surface. None makes the high-level language do pointer arithmetic, except Python's `ctypes`, which relies on `dlopen`.
- All three let native code:
  - call the language back on the same thread;
  - call it from other threads, both queued and waiting for the result;
  - run blocking C work without stopping the language's scheduler;
  - keep per-instance state.
  A design without all of these is not complete.
- Like JS values and CPython objects, Manuscript reference counts and allocation are tied to one thread, its isolate. So a foreign thread hands over C data, and the owning isolate builds the values. This is the N-API thread-safe function model.
- Go is the model for a statically linked native language: no `dlopen`, a compiler driven by the language tool, and generated C declarations for what the language exports. Manuscript goes one step further and bundles the compiler, because its runtimes (musl, mingw UCRT) are not what the system compiler targets.

## Design

The rule: **unsafe code lives in native code; the ABI is the safe contract between them; the compiler generates the C view of every declaration that crosses it.** Every `ms_*` function may be called only on the isolate thread, except those marked *any thread*.

### 1. Values

| Manuscript | C | Ownership |
| --- | --- | --- |
| `Int8` ... `Int64`, `UInt8` ... `UInt64`, `Float32`, `Float`, `Bool` | `int8_t` ... `uint64_t`, `float`, `double`, `bool` | by value; narrow integers are sign- or zero-extended per the platform ABI (today only `I8` gets `uext`, `cg.rs:14`) |
| `String`, `Bytes` | `ms_str`, `ms_bytes`; `ms_str_data`, `ms_str_len` | argument: `const *`, borrowed for the call, **copy to keep** (strings have no count, ABI.md section 3); result: trailing `out`, built with `ms_string_new` / `ms_bytes_new` |
| records and alternatives used by an extern | opaque `const ms_value *` plus generated accessors (`ms_Point_x(v)`, `ms_Shape_case(v)`, `ms_Shape_Circle_radius(v)`) and builders | argument: borrowed; result: `out`, built with generated builders |
| `List[T]`, `T?` (first); `Map`, `Set` (stage 3) | generated `ms_list_T_len/get/push`, `ms_opt_T_has/get` | as above |
| `extern type H` | `ms_object *` | argument: borrowed (`ms_retain` to keep); result: owned by Manuscript |
| `fn(A...) R` | `ms_fn *` | argument: borrowed (`ms_retain` to keep); called through `ms_call_*` / `ms_post_*` |
| `Result[T, E]` result of an extern | `uint8_t` status, `T` through `out`, `E` through `err_out` built with generated constructors (`ms_UvError_Failed(err_out, message)`) | any error type, payload or not |

- `ms header uv.ms -o uv_ms.h` lowers the module (layouts come from the MIR, `Layouts::new`) and writes:
  - a prototype for every `extern fn`;
  - accessors and builders for every record, alternative and container those signatures use;
  - one call adapter per function type.
  
  The header exposes **no struct layouts**. Records flatten to leaves and alternatives share payload slots by kind (`layout.rs:319-348`), so C sees functions, not fields. Layouts are target-independent, so one header serves every platform.
- A shim that disagrees with its declarations fails to compile; it does not corrupt memory. The header embeds `MS_ABI_VERSION`.
- Generic externs, `var` parameters and defaults stay rejected for user externs, because a C function has one signature.
- A function value passed to a user extern escapes: the ownership pass makes it own its captures. This is the rule `KEPT_CALLBACKS` applies to three bundled natives today (`crates/ms-check/src/stdlib.rs:94`), and it needs no marker.
- Buffers C keeps: Manuscript `Bytes` cannot be lent past a call, because values move. A library buffer that outlives a call is an `extern type` whose accessor copies into `Bytes`. Zero-copy views like N-API's external buffers are not offered (Open question 2).

### 2. Native objects and per-isolate state

- `ms_object_new(size, drop)` allocates an object:
  - a runtime object header (`Obj { rc, drop }`, ABI.md section 2);
  - a word for the shim's `drop`;
  - `size` bytes of zeroed, 16-byte-aligned payload at a stable address (`ms_payload`).
  
  When the last reference goes, the runtime calls `drop(payload)` and frees the object. A drop function releases native resources and may call `ms_release`; it must not call Manuscript or any `ms_call_*`.
- Asynchronous lifetimes: while a library may still touch a payload, the shim holds its own reference. It releases that reference in the library's completion callback, for libuv the `uv_close` callback. Handles retain their loop; a loop's `close()` runs it until every closing handle has finished.
- Per-isolate state, in place of process globals (N-API instance data, Python module state):
  - `ms_isolate_data(key)` and `ms_set_isolate_data(key, value, drop)`, keyed by any static address;
  - `ms_on_isolate_exit(fn, arg)`, which runs when the main program or a worker ends.

### 3. Synchronous callbacks

- `ms_call_<type>(f, args...)` is generated per function type. It is written once at the Cranelift IR level, which the LLVM backend translates (`crates/ms-clif/src/llvm_ir.rs:3`). It converts C arguments to the closure's own convention, which is C only for scalars (`call_closure`, `lower.rs:2847`; implicit sret, `cg.rs:599`), and converts the result back.
- Isolate check: closures carry no owner (ABI.md section 6). So an `fn` argument to a user extern is wrapped in a small `ms_fn` object holding the closure and its isolate id and generation.
  - `ms_call_*` checks that object against the current isolate (`isolate::CURRENT`, `isolate.rs:52`). It checks a per-task count of active extern calls, not `msrt_isolate_hdr()` (`fault.rs:109`), which always returns a header.
  - On a mismatch it writes `native callback ran outside its isolate's extern call; use ms_post or ms_call_wait from other threads` and exits 67.
- Faults: the adapter runs the closure under `msrt_guard_call` (ABI.md section 7).
  - On a fault it records the report, fires the stop hooks (section 6), and returns a zeroed result.
  - Later `ms_call_*` calls in the same extern call return zero without running.
  - When the outer extern returns, generated code re-raises the fault, so it ends the task or worker normally and `join` sees it.
  - As with every guard, values not registered for cleanup in the abandoned frames leak.
- Cancellation: the callback runs under `stop_shield`, which replays a pending stop afterwards (`fault.rs:85`).
- No waiting. A synchronous callback that would park faults at the park point with `a native callback cannot wait; post the work with ms_post`. Calls that park include:
  - channel send and receive;
  - a contended `lock`;
  - `sleep`;
  - network and pipe I/O that would block, including stdout to a full pipe;
  - `TaskGroup` joins.
  
  This keeps other tasks from re-entering the library under its own C frames, the same guarantee JS and the GIL give callbacks.
- C++ exceptions and `longjmp` must not cross Manuscript frames. Generated code has no unwind tables (`cg.rs:602`). A C++ shim catches at its boundary.

### 4. Calls from any thread

- Queued call: `ms_post_<type>(f, args...)` (*any thread*), Node's thread-safe function. Arguments are C views (`const char *, size_t` for strings and bytes, scalars by value). They are copied into system memory with one block per call, and a new inbox message kind carries them to the closure's isolate (`isolate.rs:152`; today the inbox carries only token posts). The isolate builds the Manuscript values and runs the call as a new task, so it may wait like any task.
- Waiting call: `ms_call_wait_<type>(f, args..., result_out)` (*any thread*), like `PyGILState_Ensure` plus a call, or a cgo export. It posts the same way and blocks the calling OS thread until the task finishes. The result is copied back as C views into memory the caller frees with `ms_free_result`. Called from the isolate's own thread, it returns `MS_WOULD_DEADLOCK`.
- Keeping a function for other threads: `ms_retain_shared(f)` and `ms_release_shared(f)` (*any thread*) keep `f` alive. The isolate releases the closure itself.
- A function with shared references counts as a wake source, so an isolate whose tasks wait only for posted calls is not reported as deadlocked. A reference never released turns a real deadlock into a hang; the header documents this.
- After the isolate ends, both kinds of call return `MS_CLOSED`.

### 5. Blocking work and sockets

- `int ms_blocking(void (*work)(void *), void *data, void (*done)(void *))`, called inside an extern, runs `work(data)` on a native lane while the calling task parks (Go's P handoff, Python releasing the GIL, N-API async work). `work` must not touch Manuscript values.
  - The lane is separate from the pool's DNS and general lanes (`glue/pool.rs`). It starts threads on demand up to `MS_NATIVE_THREADS` (default 64), because cgo and Python place no small cap on blocking calls.
  - It never unwinds. On cancellation it returns `MS_CANCELLED` to the shim, which then returns its own error; it does not use `pool::run`, which unwinds on a stop (`pool.rs:250`).
  - `done(data)` runs on the isolate when the job ends, including after a cancellation. The isolate reaps finished jobs on its poller wake, not only at the next submit.
- `int ms_wait_socket(ms_socket s, int events, int64_t timeout_ns)` parks the calling task until a socket is ready, through the runtime poller (`msrt_task_wait_fd`; mio on Windows, `poller.rs:254`). It covers libraries that expose sockets (libcurl multi, libpq, c-ares) on all three platforms. Arbitrary descriptors are Unix-only and are not part of it.

### 6. Stop requests

- `ms_on_stop(fn, arg)` and `ms_on_stop_remove(hook)` register a function called when a stop is requested for the isolate: SIGINT, SIGTERM, `Worker.cancel`, or a recorded callback fault.
- It runs in the requesting context: a signal handler on Linux and macOS, the console-control thread on Windows, or the cancelling thread. It must therefore be async-signal-safe; `uv_async_send` is.
- Registration uses the lock-free reader-count pattern of `PublishedHdr` (`fault.rs`).

### 7. Errors and faults

- Expected failures are `Result` values: the status byte, plus `err_out` built with generated constructors (section 1).
- `ms_fault(text, length)` raises an unrecoverable error from C. Under a callback adapter it is recorded and re-raised like a Manuscript fault. Elsewhere it runs cleanups and exits 67. It never unwinds C frames.

### 8. Toolchain: `ms cc`

- `ms cc` is clang from the same pinned llvm-bundle release that provides lld, `opt` and `llc` (`scripts/lld.lock`). It ships with the musl (Linux) and mingw UCRT (Windows) headers and libraries the linker already embeds, and with the macOS SDK stubs the linker already generates. This follows `zig cc`.
- `ms cc` targets the current platform's bundled runtime by default and takes `--target` for cross builds. It can stand in for `CC` in a library's own build, for example `cmake -DCMAKE_C_COMPILER="ms cc" ...` for libuv, so libraries and shims are built at parity without a system toolchain.
- Cost: the clang binary per platform (hypothesis: tens of MB compressed, fetched on first use like the LLVM tools are today, `crates/ms-clif/src/link/bundled.rs`). Open question 4.

### 9. Linking and versioning

- Static linking only, as Go does: `ms build main.ms --link uv_shim.o --link libuv.a`.
- On Windows, the bundle also embeds the `iphlpapi`, `psapi` and `ole32` import libraries libuv needs (`lld.rs:240` lists today's set).
- `MS_ABI_CHECK()` in a shim references `ms_abi_v<N>`, which only a matching runtime defines, so a version mismatch fails at link time.
- Public names are `ms_*` aliases in `ms-rt`. The `msrt_` and `msstd_` prefixes stay reserved (`checker.rs:1256`).

### 10. Embedding (follow-up proposal)

C programs calling Manuscript (cgo's `-buildmode=c-archive`, `Py_Initialize`) reuse section 4's waiting call. The follow-up must resolve:
- A musl-built runtime archive cannot link into a glibc or MSVC host.
- The runtime installs SIGINT and SIGTERM handlers (`crates/ms-rt/src/start.rs:221`).
- A fault exits the process with 67, which a library must not do.

### Worked example: a libuv timer

Manuscript side. It passes `ms check` against stubs: records stand in for the two `extern type`s and placeholder `fn`s stand in for the externs, because today's checker rejects both.

```manuscript
import Closeable from "@std/core.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"

export extern type Loop
export extern type Timer

# A failed libuv call, with libuv's description.
export type UvError:
    case Failed(message: String)

impl Error for UvError:
    fn message() String:
        match self:
            Failed(message): return "libuv: {message}"

extern fn msuv_loop_new() Loop!UvError
extern fn msuv_loop_run(loop: Loop) Unit!UvError
extern fn msuv_loop_close(loop: Loop) Unit!UvError
extern fn msuv_timer_new(loop: Loop) Timer!UvError
extern fn msuv_timer_start(timer: Timer, every_ms: UInt64, on_tick: fn() Bool) Unit!UvError
extern fn msuv_timer_close(timer: Timer) Unit

impl Closeable for Loop:
    # Runs the loop until every closed handle has finished, then frees it.
    var fn close() Unit!:
        try msuv_loop_close(self)
        return ok(unit)

impl Closeable for Timer:
    var fn close() Unit!:
        msuv_timer_close(self)
        return ok(unit)

# Adds one tick; the timer keeps firing while this returns true.
fn tick(count: Shared[Int], limit: Int) Bool:
    var guard = lock(count)
    guard.value += 1
    return guard.value < limit

# Fires every `every_ms` until `limit` ticks, then returns the count.
export fn count_ticks(limit: Int, every_ms: UInt64) Int!UvError:
    let loop = try msuv_loop_new()
    let timer = try msuv_timer_new(loop)
    let count = share(0)
    try msuv_timer_start(timer, every_ms, fn: tick(count, limit))
    try msuv_loop_run(loop)
    return ok(count.get())
```

C side, `uv_shim.c`, against the generated `uv_ms.h`. It is illustrative; stage 4 compiles it with `ms cc` on all three platforms.

```c
#include <string.h>
#include <uv.h>
#include "uv_ms.h"      /* `ms header uv.ms`: prototypes, ms_call_fn_Bool, ms_UvError_Failed */
MS_ABI_CHECK();

typedef struct { uv_loop_t uv; uv_async_t wake; ms_stop_hook *hook; } Loop;
typedef struct { uv_timer_t uv; ms_object *self, *loop; ms_fn *on_tick; } Timer;

static uint8_t fail(int rc, ms_value *err_out) {
    const char *text = uv_strerror(rc);
    ms_UvError_Failed(err_out, text, strlen(text));
    return 1;
}

static void on_wake(uv_async_t *a) { uv_stop(a->loop); }           /* runs inside uv_run */
static void on_stop(void *arg) { uv_async_send((uv_async_t *)arg); } /* signal-safe */

uint8_t msuv_loop_new(ms_object **out, ms_value *err_out) {
    ms_object *self = ms_object_new(sizeof(Loop), NULL);
    Loop *l = ms_payload(self);
    int rc = uv_loop_init(&l->uv);
    if (rc == 0) rc = uv_async_init(&l->uv, &l->wake, on_wake);
    if (rc < 0) { ms_release(self); return fail(rc, err_out); }
    l->hook = ms_on_stop(on_stop, &l->wake);       /* Ctrl-C stops uv_run */
    *out = self;
    return 0;
}

static void on_tick(uv_timer_t *uv) {
    Timer *t = (Timer *)uv;
    if (!ms_call_fn_Bool(t->on_tick)) uv_timer_stop(uv);   /* runs the Manuscript closure */
}

static void on_closed(uv_handle_t *uv) {           /* libuv is done: drop the shim's references */
    Timer *t = (Timer *)uv;
    if (t->on_tick) ms_release(t->on_tick);
    ms_release(t->loop);
    ms_release(t->self);
}

uint8_t msuv_timer_new(ms_object *loop, ms_object **out, ms_value *err_out) {
    ms_object *self = ms_object_new(sizeof(Timer), NULL);
    Timer *t = ms_payload(self);
    int rc = uv_timer_init(&((Loop *)ms_payload(loop))->uv, &t->uv);
    if (rc < 0) { ms_release(self); return fail(rc, err_out); }
    t->self = ms_retain(self);                     /* held until on_closed */
    t->loop = ms_retain(loop);
    *out = self;
    return 0;
}

uint8_t msuv_timer_start(ms_object *timer, uint64_t every_ms, ms_fn *callback, ms_value *err_out) {
    Timer *t = ms_payload(timer);
    if (t->on_tick) ms_release(t->on_tick);
    t->on_tick = ms_retain(callback);              /* kept until on_closed */
    int rc = uv_timer_start(&t->uv, on_tick, every_ms, every_ms);
    return rc < 0 ? fail(rc, err_out) : 0;
}

void msuv_timer_close(ms_object *timer) {
    Timer *t = ms_payload(timer);
    if (!uv_is_closing((uv_handle_t *)&t->uv)) uv_close((uv_handle_t *)&t->uv, on_closed);
}
```

- The unsafe parts live in C, where libuv's headers describe them for each platform: layout, casts, `uv_close` lifetimes, and `uv_buf_t`, which differs between Unix and Windows. The Manuscript side has no address, size or cast.
- `msuv_loop_close` (not shown) removes the stop hook, closes `wake`, and runs the loop until `uv_loop_close` succeeds.
- `uv_run` blocks its isolate. Two ways keep other tasks running, both at parity:
  - run the loop in a worker;
  - run `uv_run` on a thread the shim starts and deliver events with `ms_post_*`, so each callback runs as a task and may wait. This is how Node itself sits on libuv.
- A TCP echo server adds `uv_tcp_t`, delivers reads as `Bytes` to a `fn(Bytes) Unit` callback, and writes with `uv_write`. It is the stage 4 fixture.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt-abi/include/ms_abi.h` | public contract and rules: value functions, `ms_object_new`, isolate data, `ms_post`/`ms_call_wait` support, `ms_blocking`, `ms_wait_socket`, `ms_on_stop`, `ms_fault`, `MS_ABI_CHECK` | C test archive built with `ms cc` per platform in CI |
| `crates/ms-rt` | `ms_*` aliases; object payloads; `ms_fn` with isolate id; guard, fault record and re-raise; park-in-callback fault; inbox message for posted calls built on the isolate; waiting calls; shared function references in the deadlock check; native lane; stop hooks; isolate data and exit hooks | unit tests; foreign-thread, fault-in-callback, cancel-during-blocking, stop-hook and wait-call tests per platform |
| `crates/ms-check` | user externs accept every non-generic type and `extern type`; function arguments escape; any error type | conformance accept and reject cases with exact diagnostics |
| `crates/ms-lower`, `crates/ms-clif` | values and closures by pointer; integer extension; `err_out`; adapters per function type, written once in Cranelift IR; re-raise after an extern returns | ABI round-trip test with every type, both backends, all platforms |
| `crates/ms-cli` | `ms header`, which runs lowering for layouts; `ms cc` | header golden files; `ms cc` builds libuv per platform |
| llvm-bundle, `scripts/lld.lock`, `crates/ms-clif/src/link` | add clang and C headers to the bundle; Windows: `iphlpapi`, `psapi`, `ole32` | fetch and checksum tests |
| `documentation/core-language/functions/native-functions.md`, `crates/ms-rt/ABI.md` | rewritten for shims, the header, threads, blocking and `ms cc`; ABI.md section 6 corrected (scope and channel natives also call closures) | `make docs`, example checks |
| `examples/libuv-timer`, `examples/libuv-echo` (new) | worked examples with shims | CI builds them with `ms cc` against a checksum-pinned libuv |
| parser, grammar, formatter, LSP, `stdlib/*.ms` | unchanged (no syntax); bundled natives may move to the public header later | |

## Alternatives

- **Do nothing: shims against today's ABI.** This works for scalar-only libraries. libuv cannot be bound: there are no handles or callbacks, `Int32` is rejected, and error text is lost.
- **Pointers and raw memory in Manuscript** (draft 1). Rejected: "keep c things in c and ms things in ms".
- **Pull events only** (draft 3). Rejected: "needs to be complete". It cannot bind libraries that need an answer from a callback, and it has no answer for foreign threads.
- **An N-API-style dynamic value API.** Opaque handles with run-time create and inspect calls need no generated header. But every access is a call plus a type check, and a shim can disagree with its declaration until run time. Manuscript is statically typed and compiled ahead of time, so generated accessors give the same coverage, checked at compile time.
- **Generated C structs instead of accessors.** Field access would be cheaper, but it would freeze the compiler's flattened layouts as public ABI. Accessors keep layout free to change and can be inlined in the header later.
- **The system C compiler, as cgo uses.** It does not target musl or mingw UCRT on most machines, so shims would link against the wrong C library.
- **`ctypes`/`libffi`-style calls with no shim.** These need `dlopen`, which static musl executables cannot do (Open question 3).
- **Integrating foreign loops with the poller by descriptor.** libuv on Windows has no pollable descriptor. `ms_post_*` from the loop's own thread covers that case at parity, and `ms_wait_socket` covers libraries that expose sockets.
- **A `[link]` table in `ms.toml`.** The manifest reader takes only string values, and only the program's own manifest is read. `--link` covers the libuv stages.

## Staging and verification

Each stage lands green on Linux, macOS and Windows; no platform skips.

1. **Toolchain and values.**
   - Work: `ms cc`; scalars, `String`, `Bytes`, records, alternatives, `List`, `T?`; `extern type`; error constructors; `ms header`; `MS_ABI_CHECK`; isolate data.
   - Gate: a C test archive built with `ms cc` round-trips every type on both backends, and a handle's drop runs exactly once.
2. **Synchronous callbacks.**
   - Work: adapters, `ms_fn` isolate check, guard and re-raise, `stop_shield`, the park fault, `ms_fault`.
   - Gate: C calls a capturing closure of each shape. A fault in a callback reaches a worker's `join`. A callback that waits faults with its message.
3. **Threads and blocking.**
   - Work: `ms_post_*`, `ms_call_wait_*`, shared references, the native lane, `ms_wait_socket`, `ms_on_stop`, `Map`/`Set` accessors.
   - Gate: a C thread posts 10,000 calls that all run; waiting calls return results; cancelling during `ms_blocking` returns `MS_CANCELLED` and `done` runs; SIGINT to a program blocked in C exits 130 through its hook.
4. **libuv.**
   - Work: timer and TCP echo server, with the loop on the main isolate, in a worker, and on a shim thread posting calls; libuv built by `ms cc`.
   - Gate: every variant runs on all three platforms, and the leak check is clean.
- Go/no-go after stage 2: if adapters or re-raise need changes to the fault or task machinery beyond the guard, stop and report.
- Checks per stage:
  - `cargo fmt --all --check`
  - `cargo clippy --workspace --all-targets -- -D warnings`
  - `cargo nextest run --workspace`
  - `make verify`
  - `make verify-full` before stage 4 merges.

## Open questions

1. **Callbacks that wait.** Recommended: a synchronous callback faults if it would wait (the JS and GIL guarantee), and posted calls may wait. The alternative is to allow waiting and make re-entrancy the shim's responsibility.
2. **Zero-copy buffers.** Recommended: copy into `Bytes` now and add external `Bytes` (memory owned by a native object) only if a benchmark shows copies matter. The alternative is to design it now.
3. **Dynamic loading.** Recommended: stay static, like Go, which keeps single-binary executables. The alternative is a dynamically linked Linux build, which would make `dlopen` and `ctypes`-style calls possible.
4. **Bundling clang.** Recommended: ship `ms cc` from the existing llvm-bundle, fetched on first use. The alternative is to require users to install a musl/mingw-targeting compiler themselves.
