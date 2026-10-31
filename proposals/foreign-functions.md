# Foreign functions: a hardened native ABI for C libraries such as libuv

## Summary

- Problem: a program cannot use a C library such as libuv. `extern fn` crosses only `Int`, `Float`, `Bool` and borrowed `String`, natives cannot hand Manuscript a resource, and errors lose their text.
- Change: C things stay in C, Manuscript things in Manuscript. A binding is a small C shim written against a versioned, public `ms_abi.h`, plus a Manuscript module of typed `extern` declarations. The ABI grows by what libuv needs: sized numbers and `Bytes`, user `extern type` handles that C allocates and Manuscript owns, errors with a message, and a stop hook.
- Events are pulled, not pushed: libuv's C callbacks queue events inside the shim, and Manuscript reads them as values with `for event in loop:`. No Manuscript code ever runs inside C, so there is no callback ABI, fault barrier or re-entrancy rule to define.
- Manuscript code stays memory safe and reads like any other: handles close at scope end, events are a Manuscript `type`, failures flow through `try` and `match`. No `Pointer`, no raw memory, no new syntax.
- Decision requested: approve the direction and the three open questions.

## Status

- Proposal, 2026-10-31, checked against `d4a94aa9`. Nothing implemented.
- Direction (Chinmay, 2026-10-31): "design a process /ffi to enable integrating with other external software"; "use case could be to integrate with libuv for instance"; "by process i meant a way for manuscript to do this"; "should we harden the ms abi instead of brining all unsafe behavior into ms?"; "ms is supposed to be the language where code will flow like a stream"; "keep c things in c and ms things in ms".
- History (git): the first draft put `Pointer`, raw `Memory`, function pointers and pinned `Shared` values in Manuscript; replaced per the direction above. The second draft let C keep and call Manuscript closures.
- Skeptical reviews (independent subagents, against source), both "revise":
  - First draft: callbacks must check isolate registration, not `msrt_isolate_hdr()` (`crates/ms-rt/src/fault.rs:100` never fails); a loop blocked in C needs a stop hook; Windows needs more import libraries; a `[link]` manifest table does not help vendored bindings. Kept below.
  - Second draft: closure code does not follow the C ABI beyond scalar arguments and one scalar result (`call_closure`, `crates/ms-clif/src/lower.rs:2847`, multi-value returns via implicit sret, `cg.rs:599`); `extern type` needed a lifetime rule because `uv_close` is asynchronous; the pull-based design was the unevaluated smallest version and removes all callback machinery; the error message needs an out-parameter, not hidden state. All folded in; callbacks are deferred (Alternatives).
- Standing direction: Manuscript first (Rust only for small general primitives); Linux, macOS and Windows parity; the declared name is the symbol (no `as`, `bindings.json` removed); one `Closeable` whose `close()` returns `Unit!`; `T!E` shorthand.

## Problem

- Verified: the types a user extern may use are fixed (`crates/ms-check/src/checker.rs:1268`):

  ```text
  extern fn uv_timer_init(loop: Int, timer: Int) Int32
  a.ms:1:48: type: extern result has type Int32, which cannot cross the native boundary; return Int, Float, Bool, String, Unit, or a Result of them
  ```

- Verified: `extern type` is rejected outside bundled modules (`checker.rs:732`), so a native cannot return a libuv loop or timer as a typed value that closes itself.
- Verified: an extern error type must be payload-free (`checker.rs:1306`), so `uv_strerror` text is lost.
- Verified: `ms_abi.h` is 33 lines and declares only `ms_str` and `msrt_string_from_bytes` (`crates/ms-rt-abi/include/ms_abi.h`). Handles, bytes, faults and cancellation are internal Rust.
- Why not move the unsafety into Manuscript: every binding would do address arithmetic, casts and manual frees in `.ms`. Building libuv already needs a C compiler, so a shim adds a file, not a toolchain.
- Non-goals: dynamic loading (`dlopen` is unavailable in static musl executables, `proposals/bundled-linker.md`); C calling Manuscript code (deferred, Alternatives); calling into a library from a thread Manuscript does not run; generating shims from headers.

## Design

The rule: **unsafe code lives in native code; the ABI is the safe contract between them.** A native receives and returns only Manuscript values whose ownership the ABI defines, and it never runs Manuscript code.

### What crosses the boundary

| Manuscript | C (`ms_abi.h`) | Ownership |
| --- | --- | --- |
| `Int8` ... `Int64`, `UInt8` ... `UInt64`, `Float32`, `Float`, `Bool` | `int8_t` ... `uint64_t`, `float`, `double`, `bool` | by value |
| `String`, `Bytes` argument | `const ms_str *`, `const ms_bytes *` | borrowed for the call |
| `String`, `Bytes` result | trailing `ms_str *out`, `ms_bytes *out` | owned by Manuscript, built with `ms_string_new`, `ms_bytes_new` |
| `extern type H` argument | `ms_object *` | borrowed; `ms_retain` to keep it |
| `extern type H` result | `ms_object *` from `ms_object_new` | owned by Manuscript |
| `Result[T, E]` result | `uint8_t` status, `T` through `out` | as today; plus a message out-parameter (below) |

- Narrow integers are sign- or zero-extended as the platform C ABI requires (Apple arm64 requires the caller to). Today only `I8` gets `uext` (`crates/ms-clif/src/cg.rs:14`); signed types get `sext`.
- Still rejected for user externs: generics, `var` parameters, defaults, function values, records, lists, maps, optionals. The Manuscript side of a binding builds those from the types above.
- The `msrt_`/`msstd_` prefixes stay reserved (`checker.rs:1257`). The header's public names are `ms_*`, thin aliases in `ms-rt`, so internal names can change behind them.

### Handles: `extern type`

- `ms_object *ms_object_new(size_t size, void (*drop)(void *payload))` returns a runtime object (`Obj { rc, drop }`, ABI.md section 2) followed by one word holding the shim's `drop` and then `size` bytes of payload, zeroed and 16-byte aligned. `ms_payload(obj)` returns the payload address, which never moves, so a library may keep a pointer into it (a `uv_timer_t`).
- When the last reference goes, the runtime calls the shim's `drop(payload)` and then frees the object. A drop function may only release native resources and call `ms_release`; it must not call into a library that can run callbacks.
- Lifetime rule for libraries that finish asynchronously: while a library may still touch a payload, the shim holds its own reference (`ms_retain(obj)`), and it releases that reference in the library's completion callback. For libuv: retain at `uv_timer_init`, `uv_close` in the handle's `close()`, `ms_release` in the close callback. A handle also retains its loop.
- A loop is `Closeable`: its `close()` runs the loop until every closing handle has finished (`uv_run` until `uv_loop_close` stops returning `UV_EBUSY`), so close callbacks run and the last references drop before the loop's memory goes.
- Counts are isolate-local, like every count in the runtime: a shim touches a handle only on the isolate that passed it.

### Errors with a message

- An error type may have one case whose only field is `message: String`. Its extern gets a trailing `ms_str *message_out` after `out`. A native returns that case's status (case index + 1, as today) and writes the message with `ms_string_new` into `message_out`; for other statuses it leaves it unwritten. This extends the status-and-out convention of ABI.md section 1 and keeps no hidden state.

### Events are values

- A library's C callbacks write into a queue inside the shim's loop payload. They never call Manuscript.
- The shim exposes `next` as one extern: if the queue is empty, it runs `uv_run(loop, UV_RUN_ONCE)` until an event is queued or nothing is left to run, then returns the event kind (0 for none), with accessors for the current event's fields (`Int`, `Bytes`, `String`).
- The Manuscript module turns kinds into a Manuscript `type` and implements `Iterator` (`stdlib/core.ms:77`), so a program walks events with `for` and `match`, like a stream. Errors are an event case, so the walk stays flat.
- Blocking: `next` blocks its isolate while libuv waits. A program whose main loop is libuv runs it on the main isolate; one that also serves other tasks runs it in a worker (`WorkerGroup.spawn`) and exchanges values over the worker's channel. Integrating with the runtime poller (`uv_backend_fd`) is not possible on Windows, where libuv uses IOCP (Alternatives).

### Stopping a loop blocked in C

- A stop request (SIGINT, SIGTERM, `Worker.cancel`) sets a flag that Manuscript polls (ABI.md section 7); code blocked in `uv_run` never polls, so without help Ctrl-C ends in the 30 s forced exit.
- `ms_stop_hook *ms_on_stop(void (*fn)(void *), void *arg)` registers a function the runtime calls when a stop is requested for this isolate; `ms_on_stop_remove(hook)` unregisters it. It runs in the requesting context: a signal handler on Linux and macOS, the console-control thread on Windows, the cancelling thread for `Worker.cancel`. So it must be async-signal-safe and thread-safe; `uv_async_send` is documented as both. Registration uses the lock-free reader-count pattern of `PublishedHdr` (`fault.rs`).
- libuv shim: the loop's `uv_async_t` callback calls `uv_stop`; `uv_run` returns; `next` returns none; the next poll in Manuscript unwinds with the usual cleanups and exit status 130 or 143.

### Versioning

- `ms_abi.h` defines `MS_ABI_VERSION`, numbered separately from the internal ABI.md version. `MS_ABI_CHECK()` in a shim references the symbol `ms_abi_v<N>`, which only a matching runtime defines, so a mismatch fails at link time with that name. Static linking makes this sufficient.
- The header states the shim rules once: never free or reallocate a Manuscript string, bytes or object; build results only with the `ms_*_new` constructors; keep no borrowed `ms_str`/`ms_bytes` pointer past return; touch Manuscript values only on the isolate that passed them; never block a drop function.

### Worked example: a libuv timer

Manuscript side. Checked with `ms check` against stubs (records stand in for the two `extern type`s and placeholder `fn`s for the externs, since today's checker rejects both):

```manuscript
import Closeable, Iterator from "@std/core.ms"

export extern type Loop
export extern type Timer

# A failed libuv call, with libuv's description.
export type UvError:
    case Failed(message: String)

impl Error for UvError:
    fn message() String:
        match self:
            Failed(message): return "libuv: {message}"

# What the loop reported, in order.
export type Event:
    # A timer fired; `timer` is its `id()`.
    case Tick(timer: Int)
    # The loop failed; iteration ends after this.
    case Problem(error: UvError)

extern fn msuv_loop_new() Loop!UvError
extern fn msuv_loop_next(loop: Loop) Int32!UvError
extern fn msuv_loop_event_timer(loop: Loop) Int
extern fn msuv_loop_close(loop: Loop) Unit!UvError
extern fn msuv_timer_new(loop: Loop, every_ms: UInt64) Timer!UvError
extern fn msuv_timer_id(timer: Timer) Int
extern fn msuv_timer_close(timer: Timer) Unit

let EVENT_NONE: Int32 = 0
let EVENT_TICK: Int32 = 1

impl Iterator[Event] for Loop:
    # Runs the loop until the shim has queued an event; none once nothing is left to run.
    var fn next() Event?:
        let kind = msuv_loop_next(self)
        if kind.is_error():
            return Event.Problem(kind.err())
        let code = kind.get(EVENT_NONE)
        if code == EVENT_TICK:
            return Event.Tick(msuv_loop_event_timer(self))
        return none

impl Closeable for Loop:
    # Runs the loop until every closed handle has finished, then frees it.
    var fn close() Unit!:
        try msuv_loop_close(self)
        return ok(unit)

impl Timer:
    fn id() Int: msuv_timer_id(self)

impl Closeable for Timer:
    var fn close() Unit!:
        msuv_timer_close(self)
        return ok(unit)

# Fires every `every_ms` until `limit` ticks, then returns the count.
export fn count_ticks(limit: Int, every_ms: UInt64) Int!UvError:
    var loop = try msuv_loop_new()
    let _timer = try msuv_timer_new(loop, every_ms)
    var count = 0
    for event in loop:
        match event:
            Tick(_):
                count += 1
                if count == limit:
                    return ok(count)
            Problem(failure):
                return error(failure.clone())
    return ok(count)
```

C side, `uv_shim.c` (illustrative; stage 2 compiles it on all three platforms). The parts that touch memory, layout and libuv's lifetimes:

```c
#include <string.h>
#include <ms_abi.h>
#include <uv.h>
MS_ABI_CHECK();

typedef struct { uv_loop_t uv; int64_t queue[64]; int head, tail; int64_t current; } Loop;
typedef struct { uv_timer_t uv; ms_object *self, *loop; } Timer;

static void on_tick(uv_timer_t *uv) {              /* C only: queue, never call Manuscript */
    Timer *t = (Timer *)uv;
    Loop *l = ms_payload(t->loop);
    l->queue[l->tail++ % 64] = (int64_t)(intptr_t)t;
}

static void on_closed(uv_handle_t *uv) {           /* libuv is done: drop the shim's references */
    Timer *t = (Timer *)uv;
    ms_release(t->loop);
    ms_release(t->self);
}

uint8_t msuv_timer_new(ms_object *loop, uint64_t every_ms, ms_object **out, ms_str *message_out) {
    ms_object *self = ms_object_new(sizeof(Timer), NULL);
    Timer *t = ms_payload(self);
    int rc = uv_timer_init(&((Loop *)ms_payload(loop))->uv, &t->uv);
    if (rc == 0) rc = uv_timer_start(&t->uv, on_tick, every_ms, every_ms);
    if (rc < 0) {
        const char *text = uv_strerror(rc);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        ms_release(self);   /* real shim: uv_close first if init succeeded */
        return 1;           /* UvError.Failed */
    }
    t->self = ms_retain(self);                     /* held until on_closed */
    t->loop = ms_retain(loop);
    *out = self;
    return 0;
}

void msuv_timer_close(ms_object *self) {
    Timer *t = ms_payload(self);
    if (!uv_is_closing((uv_handle_t *)&t->uv)) uv_close((uv_handle_t *)&t->uv, on_closed);
}
```

- The unsafe parts (struct layout, casts, `uv_close` lifetimes, `uv_buf_t` differing between Unix and Windows) are in C, where libuv's headers describe them correctly per platform.
- The Manuscript side has no address, size or cast: handles close at scope end, events are values, failures are `Result`s.
- Build: `cc -c -I <ms>/include -I <libuv>/include uv_shim.c`, then `ms build main.ms --link uv_shim.o --link libuv.a`. Archives must match the bundled toolchain (musl on Linux, mingw UCRT on Windows, `proposals/bundled-linker.md`); the documentation gives the commands per platform.
- Windows: libuv also needs `iphlpapi`, `psapi` and `ole32`, which the bundle does not embed today (`crates/ms-clif/src/link/lld.rs:240`); stage 2 adds them.
- A TCP echo server adds `Read(connection: Int, data: Bytes)` and `Accepted(connection: Int)` events and a `write(connection, data: Bytes)` extern; it is the stage 2 fixture.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt-abi/include/ms_abi.h` | the public contract: `ms_str`, `ms_bytes`, `ms_object`, constructors, `ms_retain`/`ms_release`, `ms_payload`, `ms_on_stop`, `MS_ABI_CHECK`, the rules | C test archive compiled per platform in CI |
| `crates/ms-rt` | `ms_*` aliases; `ms_object_new` (header, shim drop word, zeroed aligned payload); stop hooks called from the signal handler, the Windows console handler and `msrt_worker_cancel`; `ms_abi_v<N>` | unit tests; stop-hook tests per platform |
| `crates/ms-check` | user externs: sized types, `Bytes`, `extern type`, error case with `message` | conformance accept and reject cases with exact diagnostics |
| `crates/ms-lower`, `crates/ms-clif` (both backends) | handles as pointers; sign and zero extension; `message_out` | ABI round-trip test calling C with every type |
| `crates/ms-clif/src/link` | Windows: embed `iphlpapi`, `psapi`, `ole32` | Windows libuv example links |
| `stdlib/*.ms`, ownership pass, `KEPT_CALLBACKS` | unchanged (no function values cross user externs) | |
| `documentation/core-language/functions/native-functions.md` | rewritten around writing a shim; per-platform build commands | `make docs`, example checks |
| `examples/libuv-timer` (new) | the worked example with its shim | CI builds it against a checksum-pinned libuv |
| parser, grammar, formatter, LSP | unchanged (no syntax) | |

## Alternatives

- **Do nothing: shims against today's ABI.** Works for scalar-only libraries. libuv cannot be bound: there is no handle type, `Int32` cannot cross, and error text is lost.
- **Raw pointers in Manuscript** (first draft: `Pointer`, `Memory`, `callback(f)`, pinned `Shared`). No C file per library, but bindings become address arithmetic and manual lifetimes in `.ms`, an unsafe dialect. Rejected by the owner's direction.
- **C calls Manuscript closures** (second draft). Lets a library call back directly, but closure code follows the C ABI only for scalar arguments and one scalar result (`lower.rs:2847`, `cg.rs:599`), so the compiler would emit a C-ABI adapter per callback type in both backends; and it needs an isolate check, a fault barrier that still reports to a worker's joiner, a cancellation shield (`stop_shield`, `fault.rs:85`), a rule against re-entering the library from a parked callback, and ownership of closures kept by C. The pull design needs none of it for libuv. Revisit for a library that must get an answer from its callback (SQLite's busy handler, a comparator); stage it then with these rules.
- **Integrate a library's loop with the runtime poller** (`uv_backend_fd` plus `msrt_task_wait_fd`). Keeps the main isolate's other tasks running, but libuv on Windows has no pollable descriptor (IOCP), so it breaks parity. Deferred.
- **A `[link]` table in `ms.toml`.** The manifest reader accepts only string values in `[project]` and `[aliases]`, and only the program's manifest is read, so a vendored binding could not carry its own inputs. `--link` covers the libuv stages.
- **Dynamic libraries.** Impossible on static musl Linux; rejected for parity.

## Staging and verification

Each stage lands green on Linux, macOS and Windows; no platform skips.

1. **The ABI.** Sized types, `Bytes`, user `extern type` with `ms_object_new`, error messages, `ms_on_stop`, the header and `MS_ABI_CHECK`. Gate: a C test archive round-trips every type on both backends; a handle's drop runs exactly once after its last reference; SIGINT to a program blocked in a C wait exits 130 through its hook.
2. **libuv.** `examples/libuv-timer` and a TCP echo server with shims, against libuv 1.x archives fetched by checksum in CI; Windows import libraries. Gate: both run on all three platforms, including a loop hosted in a worker and stopped by `Worker.cancel`; leak check clean.
- Go/no-go after stage 1: if the stop hook cannot be made async-signal-safe on one platform, stop and report.
- Checks per stage: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo nextest run --workspace`, `make verify`; `make verify-full` before stage 2 merges.

## Open questions

1. **Header names.** Public `ms_*` aliases (recommended: the `msrt_` names stay free to change), or publish the existing `msrt_*` symbols directly.
2. **Callbacks into Manuscript.** Leave them out until a bound library needs an answer from a callback (recommended), or design them now with the rules listed under Alternatives.
3. **Bundled natives.** Move them to the public header over time so the stdlib uses the same contract (recommended, per module, as each is touched), or keep the stdlib on the internal ABI.
