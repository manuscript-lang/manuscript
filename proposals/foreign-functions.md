# Foreign functions: what `ms_abi.h` must provide

## Summary

- Problem: a program cannot use a C library such as libuv. `ms_abi.h` today declares only a borrowed string view and one string constructor. A native cannot hand Manuscript a resource, call Manuscript back, run blocking work without stalling every task, or report error text.
- Change: grow `ms_abi.h` into the complete, versioned contract for C shims. C code stays in C and Manuscript code stays in Manuscript: a binding is a shim written against this one header, plus typed `extern fn` declarations in `.ms`.
- The header has eleven groups: version, status codes, strings and bytes, values, lists, native objects, errors and faults, calls into Manuscript (same thread and any thread), blocking work and sockets, stop requests, and per-isolate state. Together they cover the use cases of Node's N-API, Python's C API and Go's cgo; the doc maps each use case to its entries.
- Manuscript code stays memory safe: no pointers, no raw memory, no new syntax. Records, optionals and other compound types are converted in Manuscript wrappers, not in C.
- Decision requested: approve the header and the three open questions.

## Status

- Proposal, 2026-10-31, checked against `d4a94aa9`. Nothing implemented.
- Direction (Chinmay, 2026-10-31):
  - "design a process /ffi to enable integrating with other external software"
  - "use case could be to integrate with libuv for instance"
  - "should we harden the ms abi instead of brining all unsafe behavior into ms?"
  - "ms is supposed to be the language where code will flow like a stream"
  - "keep c things in c and ms things in ms"
  - "the interop needs to be complete ... how do other languages do this like node or python or go"
  - "lets focus this on what we can do in the msabi.h file to achieve all the use cases"
- History (git): earlier drafts put pointers in Manuscript, then pulled events only, then added generated headers, `ms cc` and embedding. This version is scoped to the header and what stands behind it.
- Review findings kept from four independent skeptical reviews:
  - Closure code follows the C ABI only for scalars (`call_closure`, `crates/ms-clif/src/lower.rs:2847`), so C calls closures through a runtime entry, not directly.
  - Thread checks use isolate registration (`isolate::CURRENT`, `crates/ms-rt/src/isolate.rs:52`); `msrt_isolate_hdr()` always returns a header (`fault.rs:109`).
  - Values cannot be built on a foreign thread, because the arena forbids cross-thread frees (`glue/pool.rs:5`). Foreign threads pass C data, and the isolate builds the values.
  - A callback fault is guarded and re-raised, so a worker's `join` sees it.
  - Blocking work needs its own non-unwinding entry, because `pool::run` unwinds on a stop (`pool.rs:250`).
  - Libraries that finish asynchronously need a lifetime rule.
- Skeptical review of this revision: the reviewer said revise, and every finding is folded in:
  - Manuscript values never cross threads; cross-thread calls take only plain C data.
  - Generated code pre-fills outputs, so a shim that writes the wrong one or none cannot cause an undefined drop.
  - `ms_list` carries its element kind.
  - Entry points have versioned names. A `used` check symbol would not survive `--gc-sections` (`link/lld.rs:189`).
  - The header has a C++ guard and a named union.
  - `ms_blocking` takes `cancel` and always waits for `work`.
  - `ms_fn_hold` replaces "every function is a wake source", and `ms_post` has backpressure.
  - `ms_wait_sockets` takes several sockets at full `SOCKET` width and reports hang-up.
  - Added: `ms_str_cstring` and `code_out`.
  - Status codes are distinct.
  - The example keeps library memory in C and frees it from the completion callback.

## Problem

- Verified: today's header (`crates/ms-rt-abi/include/ms_abi.h`, 33 lines) declares `ms_str`, `ms_str_len`, `ms_str_data` and `msrt_string_from_bytes`, nothing else.
- Verified: what a user extern may use is limited by the checker:
  - argument and result types are only `Int`, `Float`, `Bool`, `String` (`crates/ms-check/src/checker.rs:1268`);
  - error types must be payload-free (`checker.rs:1306`);
  - `extern type` is bundled-only (`checker.rs:732`);
  - function values cannot be passed.
- Example (verified):

  ```text
  extern fn uv_timer_init(loop: Int, timer: Int) Int32
  a.ms:1:48: type: extern result has type Int32, which cannot cross the native boundary; return Int, Float, Bool, String, Unit, or a Result of them
  ```

- Verified: a native that blocks stalls every task on its isolate (ABI.md section 7).

## The header

`ms_abi.h` v1. Every function may be called only on the isolate thread that called into the shim, unless it is marked **any thread**. Values that cross threads are plain C data in system memory; Manuscript values never leave their isolate.

```c
#ifndef MS_ABI_H
#define MS_ABI_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#define MS_NORETURN [[noreturn]]
#else
#define MS_NORETURN _Noreturn
#endif

/* ---- 1. Version ---------------------------------------------------------------------- */
/* Every entry point is linked under a versioned name (ms_string_new is ms_string_new_v1), so a
   shim built against another version fails to link, naming the function it needs. */
#define MS_ABI_VERSION 1

/* ---- 2. Status codes ----------------------------------------------------------------- */
typedef enum ms_status {
    MS_OK = 0, MS_CANCELLED = 1, MS_TIMEOUT = 2, MS_CLOSED = 3, MS_FAULTED = 4,
    MS_WOULD_DEADLOCK = 5, MS_FULL = 6, MS_INVALID = 7
} ms_status;

/* ---- 3. Strings and bytes ------------------------------------------------------------ */
typedef struct ms_str   { void *ptr_word; size_t tagged; } ms_str;          /* String (StrVal) */
typedef struct ms_bytes { uint8_t *ptr; size_t len; size_t cap; } ms_bytes; /* Bytes (VecVal) */
size_t         ms_str_len(const ms_str *s);
const uint8_t *ms_str_data(const ms_str *s);       /* not NUL-terminated                     */
char          *ms_str_cstring(const ms_str *s);    /* any thread: malloc'd NUL-terminated copy;
                                                      NULL if s contains NUL; free with free() */
size_t         ms_bytes_len(const ms_bytes *b);
const uint8_t *ms_bytes_data(const ms_bytes *b);
void ms_string_new(const uint8_t *data, size_t len, ms_str *out);   /* copies into out        */
void ms_bytes_new(const uint8_t *data, size_t len, ms_bytes *out);  /* copies into out        */

/* ---- 4. Values ----------------------------------------------------------------------- */
typedef struct ms_object ms_object;
typedef struct ms_fn     ms_fn;
typedef struct ms_list   ms_list;
typedef enum ms_kind {
    MS_UNIT, MS_BOOL, MS_INT, MS_UINT, MS_FLOAT, MS_STRING, MS_BYTES,
    MS_OBJECT, MS_LIST, MS_FN                      /* same thread only                       */
} ms_kind;
typedef struct ms_value {
    ms_kind kind;
    union {
        bool b; int64_t i; uint64_t u; double f;   /* sized types widen; narrowing is checked */
        struct { const uint8_t *data; size_t len; } buf;   /* MS_STRING, MS_BYTES: a view    */
        ms_object *object; const ms_list *list; ms_fn *fn;
    } as;
} ms_value;
/* String and bytes results from ms_list_get, ms_call and ms_call_wait are malloc'd copies. */
void ms_value_free(ms_value *v);                   /* any thread                             */

/* ---- 5. Lists ------------------------------------------------------------------------ */
/* A List[T] of a signature type. The list knows its element type, so get and push check kinds
   and ranges; a mismatch faults naming both types. */
size_t   ms_list_len(const ms_list *l);
ms_kind  ms_list_kind(const ms_list *l);
ms_value ms_list_get(const ms_list *l, size_t i);  /* objects and functions borrowed          */
void     ms_list_push(ms_list *out, const ms_value *v);  /* out starts as an empty list       */

/* ---- 6. Native objects (extern type) ------------------------------------------------- */
/* size bytes of zeroed payload, 16-byte aligned, at a stable address. drop(payload), which may
   be NULL, runs when the last reference goes; it may free native memory, start a library's
   asynchronous close and call ms_release, nothing else. */
ms_object *ms_object_new(size_t size, void (*drop)(void *payload));
void      *ms_payload(ms_object *o);
ms_object *ms_retain(ms_object *o);
void       ms_release(ms_object *o);

/* ---- 7. Errors and faults ------------------------------------------------------------ */
/* A fallible extern returns uint8_t: 0 is ok, n is the n-th case of its error type. If any case
   has a `code: Int` field, a trailing int64_t *code_out follows; if any has `message: String`, a
   trailing ms_str *message_out follows. Outputs arrive holding valid empty values; the caller
   reads only the fields of the returned case and drops every output either way. */
/* Unrecoverable. Runs cleanups like a Manuscript fault; under a task guard it jumps over the
   calling C frames, so call it only when the library's state is consistent. */
MS_NORETURN void ms_fault(const char *text, size_t len);

/* ---- 8. Calling Manuscript functions ------------------------------------------------- */
/* Same thread, inside an extern call. Arguments are checked against f's signature. After a
   fault in f it returns MS_FAULTED (the fault is re-raised when the extern returns) and later
   calls return MS_FAULTED without running. f may not wait: a park faults. */
ms_status ms_call(ms_fn *f, const ms_value *args, size_t count, ms_value *result);
/* any thread. Arguments may be only BOOL, INT, UINT, FLOAT, STRING, BYTES (else MS_INVALID); they
   are copied, and the call runs as a new task on f's isolate, where it may wait. MS_FULL when
   more than 1024 calls are queued for f; MS_CLOSED after the isolate has ended. */
ms_status ms_post(ms_fn *f, const ms_value *args, size_t count);
/* any thread except f's own isolate (MS_WOULD_DEADLOCK). Like ms_post, then blocks until the
   call returns; the result is a copy (same kinds). */
ms_status ms_call_wait(ms_fn *f, const ms_value *args, size_t count, ms_value *result);
ms_fn *ms_fn_retain(ms_fn *f);                     /* any thread                             */
void   ms_fn_release(ms_fn *f);                    /* any thread; the closure goes on its isolate */
/* any thread. While held, f keeps its isolate waiting for posts instead of reporting a
   deadlock (N-API's ref/unref). A retained but unheld f does not keep the isolate alive. */
void   ms_fn_hold(ms_fn *f, bool hold);

/* ---- 9. Blocking work and sockets ---------------------------------------------------- */
/* Inside an extern: runs work(data) on a native thread while the calling task parks, so other
   tasks keep running. work must not touch Manuscript values. On cancellation, cancel(data)
   (may be NULL) runs on the isolate, for example sqlite3_interrupt; ms_blocking always waits
   for work to return, then returns MS_OK or MS_CANCELLED. */
ms_status ms_blocking(void (*work)(void *data), void (*cancel)(void *data), void *data);
#ifdef _WIN32
typedef uintptr_t ms_socket;                       /* SOCKET                                 */
#else
typedef int ms_socket;
#endif
enum { MS_READABLE = 1, MS_WRITABLE = 2, MS_HANGUP = 4 };
typedef struct ms_socket_wait { ms_socket socket; int events; int ready; } ms_socket_wait;
/* Inside an extern: parks the calling task until one of the sockets is ready (its `ready` is
   set), the timeout passes (negative: none) or the task is cancelled. */
ms_status ms_wait_sockets(ms_socket_wait *items, size_t count, int64_t timeout_ns);

/* ---- 10. Stop requests --------------------------------------------------------------- */
typedef struct ms_stop_hook ms_stop_hook;
/* fn(arg) runs when a stop is requested for this isolate (SIGINT, SIGTERM, Worker.cancel, a
   callback fault), from a signal handler or another thread: it must be async-signal-safe. */
ms_stop_hook *ms_on_stop(void (*fn)(void *arg), void *arg);
void          ms_on_stop_remove(ms_stop_hook *h);

/* ---- 11. Per-isolate state ----------------------------------------------------------- */
/* key: any static address. Replaces process globals so a shim works in several workers; drop
   runs when the value is replaced or the isolate ends. */
void *ms_isolate_get(const void *key);
void  ms_isolate_set(const void *key, void *value, void (*drop)(void *value));

/* ---- Rules ----------------------------------------------------------------------------- */
/* - Never free, reallocate or write a Manuscript string, bytes, list or object yourself.
   - Borrowed arguments are valid only until the extern returns: copy strings and bytes to keep
     them, ms_retain an object, ms_fn_retain a function.
   - ms_object, ms_list and Manuscript strings stay on their isolate; only ms_fn handles,
     ms_post, ms_call_wait, ms_value_free and ms_str_cstring are any thread.
   - Memory a library keeps after a call (a uv_timer_t) is C memory the shim allocates. The
     object's drop starts the library's close, and the completion callback frees it.
   - C++ exceptions and longjmp must not cross Manuscript frames.
   - Cancellation is never delivered inside C: an extern call sees it only as MS_CANCELLED from
     ms_blocking or ms_wait_sockets, or after it returns. */
#ifdef __cplusplus
}
#endif
#endif
```

### Use cases and the entries that cover them

| Use case | Example | Header entries |
| --- | --- | --- |
| Call a C function with numbers and text | `uv_strerror`, `crc32` | 3, signature types (below) |
| Pass a path to a C API | `sqlite3_open(const char *)` | 3 (`ms_str_cstring`) |
| Pass and return binary data | socket reads, compression | 3 (`ms_bytes`) |
| Pass or return a list | argv, a batch of rows | 5 |
| Own a native resource that closes at scope end | `sqlite3 *`, a libuv loop | 6, plus `impl Closeable` in `.ms` |
| A resource the library releases later | `uv_close` | 6, plus the memory rule |
| Report a failure with its code and text | `UV_EAGAIN`, `uv_strerror_r` | 7 (`code_out`, `message_out`) |
| Library calls back on the same thread | libuv timer and read callbacks, `qsort` comparators, SQLite busy handler | 8 (`ms_call`) |
| Library calls back from its own thread | libuv loop on its own thread, audio callbacks, gRPC completion queues | 8 (`ms_post`, `ms_call_wait`, `ms_fn_hold`) |
| Run a blocking C call without stalling tasks | `sqlite3_step`, a synchronous HTTP call | 9 (`ms_blocking`, with `sqlite3_interrupt` as `cancel`) |
| Integrate a library that exposes sockets | libcurl multi, libpq, c-ares | 9 (`ms_wait_sockets`) |
| Ctrl-C reaches a loop blocked in C | `uv_run` | 10 (`ms_on_stop` calling `uv_async_send`) |
| One shim used by several workers | per-worker connection pools | 11 |
| Unrecoverable error in C | violated library invariant | 7 (`ms_fault`) |
| Shim built against another runtime version | upgrade | 1 (versioned names) |

The capabilities N-API, the CPython C API and cgo share are values, wrapped objects with finalizers, same-thread callbacks, queued and waiting calls from other threads with keep-alive control, blocking work with interruption, socket readiness, instance state and exception rules. Each has a row above. Dynamic loading and embedding are non-goals (below).

### Manuscript signature types

The checker accepts these in a user `extern fn`. Records, alternatives, maps, optionals, generics, `var` parameters and defaults are converted in an ordinary Manuscript wrapper around the extern. A call with several results returns an `extern type` with accessor externs.

| Manuscript | C parameter | C result |
| --- | --- | --- |
| `Int8` ... `Int64`, `UInt8` ... `UInt64`, `Float32`, `Float`, `Bool` | same-width C type, extended per platform ABI | same |
| `String`, `Bytes` | `const ms_str *`, `const ms_bytes *` (borrowed) | trailing `ms_str *out`, `ms_bytes *out` |
| `List[T]`, `T` a scalar, `String`, `Bytes` or `extern type` | `const ms_list *` (borrowed) | trailing `ms_list *out` |
| `extern type H` | `ms_object *` (borrowed) | `ms_object *` (owned by Manuscript) |
| `fn(A...) R`, each `A` a row above and `R` one or `Unit` | `ms_fn *` (borrowed; `ms_fn_retain` to keep) | not allowed |
| `Unit` | not allowed | `void` |
| `Result[T, E]`; `E` cases carry nothing, `code: Int`, `message: String`, or both | not allowed | `uint8_t` status, `T` through `out`, then `code_out`, `message_out` as needed |

## Behind the header

- **Values.**
  - `ms_str` and `ms_bytes` are the runtime's `StrVal` and `VecVal` (ABI.md sections 3 and 4).
  - `ms_list` is `{VecVal *, element descriptor, element kind}`. The descriptor is the one the compiler already passes to generic list natives (ABI.md sections 1 and 5). The kind records signedness and width, which a POD descriptor does not.
  - Narrow integers gain sign and zero extension at the call; today only `I8` gets `uext` (`cg.rs:14`).
- **Outputs.** Generated code fills `out`, `code_out` and `message_out` with valid empty values before the call, then drops all of them after it. A shim that writes the wrong output, or none, therefore causes no undefined drop. This changes today's "uninitialised `out`" rule (ABI.md section 1) for user externs only.
- **Objects.** `ms_object_new` allocates a runtime object: the `Obj { rc, drop }` header (ABI.md section 2), a word for the shim's `drop`, and padding, so the payload starts at offset 32. `extern type` becomes legal in user modules, as an opaque handle with no fields.
- **Functions.** A function value passed to a user extern is wrapped by the compiler in an `ms_fn` holding:
  - the closure;
  - its isolate id and generation;
  - an atomic count;
  - a hold flag;
  - a pointer to a compiler-emitted invoke thunk for its type. The thunk is written once at the Cranelift IR level, which the LLVM backend translates. It converts `ms_value` arguments to the closure's own convention and back, and checks kinds and ranges.

  The ownership pass treats the function as escaping, so it owns its captures (the rule `KEPT_CALLBACKS` applies to three bundled natives, `crates/ms-check/src/stdlib.rs:94`).
- **`ms_call`.**
  - It checks that the current thread is the `ms_fn`'s isolate and that an extern call is active, using a per-task count.
  - It runs the thunk under `msrt_guard_call` and `stop_shield` (ABI.md section 7, `fault.rs:85`). The guard's jump target is inside `ms_call`, so a fault skips only Manuscript frames.
  - On a fault it records the report and fires the stop hooks. Generated code re-raises the fault after the extern returns, so a worker's `join` sees it.
  - A park inside the call faults with `a native callback cannot wait; use ms_post`.
- **`ms_post` and `ms_call_wait`.**
  - Arguments are copied into system memory and carried to the isolate by a new inbox message kind (`isolate.rs:152`; today the inbox carries only token posts).
  - The isolate builds the values and runs the call as a task.
  - A held `ms_fn` counts as a wake source in the deadlock check.
- **`ms_blocking`.**
  - Work runs on a native lane, separate from the pool's DNS and general lanes (`glue/pool.rs`). The lane starts threads on demand, up to `MS_NATIVE_THREADS` (default 64).
  - It never unwinds, and it always waits for `work`. A `work` that never returns is cut off by the existing 30 s forced exit.
- **`ms_wait_sockets`** is a new poller entry that registers several sockets at once, with full `SOCKET` width on Windows (mio, `poller.rs:254`). `msrt_task_wait_fd` takes one `i32` (`task.rs:1119`), so it cannot serve here.
- **`ms_on_stop`.** It is called from the signal handler on Linux and macOS, from the console-control thread on Windows, and from `msrt_worker_cancel`. Registration uses the lock-free reader-count pattern of `PublishedHdr`.
- **Names.** Public names are `ms_*`, defined in `ms-rt` under their `_v1` names. The `msrt_` and `msstd_` prefixes stay reserved (`checker.rs:1256`). `msrt_string_from_bytes` stays as an alias of `ms_string_new`.

## Worked example: a libuv timer

Manuscript side. It passes `ms check` against stubs: records stand in for the two `extern type`s and placeholder `fn`s for the externs, because today's checker rejects both.

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

C side, `uv_shim.c`, using only `ms_abi.h` and `uv.h`. It is illustrative; stage 3 compiles it on all three platforms.

```c
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#include <ms_abi.h>

/* libuv keeps these after a call, so they are C memory; the objects hold pointers to them. */
typedef struct { uv_loop_t uv; uv_async_t wake; ms_stop_hook *hook; } Loop;
typedef struct { uv_timer_t uv; ms_object *loop; ms_fn *on_tick; } Timer;

static uint8_t fail(int rc, ms_str *message_out) {
    char text[256];
    uv_strerror_r(rc, text, sizeof text);
    ms_string_new((const uint8_t *)text, strlen(text), message_out);
    return 1;                                      /* UvError.Failed */
}

static void on_wake(uv_async_t *a) { uv_stop(a->loop); }
static void on_stop(void *arg) { uv_async_send((uv_async_t *)arg); }  /* signal-safe */
static void close_any(uv_handle_t *h, void *arg) { if (!uv_is_closing(h)) uv_close(h, NULL); }

static void loop_drop(void *payload) {             /* only C callbacks run from here on */
    Loop *l = *(Loop **)payload;
    if (!l) return;
    ms_on_stop_remove(l->hook);
    uv_walk(&l->uv, close_any, NULL);
    uv_run(&l->uv, UV_RUN_DEFAULT);
    uv_loop_close(&l->uv);
    free(l);
}

uint8_t msuv_loop_new(ms_object **out, ms_str *message_out) {
    Loop *l = calloc(1, sizeof *l);
    int rc = uv_loop_init(&l->uv);
    if (rc < 0) { free(l); return fail(rc, message_out); }
    rc = uv_async_init(&l->uv, &l->wake, on_wake);
    if (rc < 0) { uv_loop_close(&l->uv); free(l); return fail(rc, message_out); }
    l->hook = ms_on_stop(on_stop, &l->wake);       /* Ctrl-C stops uv_run */
    ms_object *self = ms_object_new(sizeof(Loop *), loop_drop);
    *(Loop **)ms_payload(self) = l;
    *out = self;
    return 0;
}

static void on_tick(uv_timer_t *uv) {
    Timer *t = (Timer *)uv;
    ms_value keep;
    if (ms_call(t->on_tick, NULL, 0, &keep) != MS_OK || !keep.as.b) uv_timer_stop(uv);
}

static void on_closed(uv_handle_t *uv) {           /* libuv is done: free the C memory */
    Timer *t = (Timer *)uv;
    if (t->on_tick) ms_fn_release(t->on_tick);
    ms_release(t->loop);
    free(t);
}

static void timer_drop(void *payload) {            /* last Manuscript reference gone */
    Timer *t = *(Timer **)payload;
    if (t && !uv_is_closing((uv_handle_t *)&t->uv)) uv_close((uv_handle_t *)&t->uv, on_closed);
}

uint8_t msuv_timer_new(ms_object *loop, ms_object **out, ms_str *message_out) {
    Timer *t = calloc(1, sizeof *t);
    int rc = uv_timer_init(&(*(Loop **)ms_payload(loop))->uv, &t->uv);
    if (rc < 0) { free(t); return fail(rc, message_out); }
    t->loop = ms_retain(loop);                     /* the loop outlives its timers */
    ms_object *self = ms_object_new(sizeof(Timer *), timer_drop);
    *(Timer **)ms_payload(self) = t;
    *out = self;
    return 0;
}

uint8_t msuv_timer_start(ms_object *timer, uint64_t every_ms, ms_fn *callback, ms_str *message_out) {
    Timer *t = *(Timer **)ms_payload(timer);
    if (t->on_tick) ms_fn_release(t->on_tick);
    t->on_tick = ms_fn_retain(callback);
    int rc = uv_timer_start(&t->uv, on_tick, every_ms, every_ms);
    return rc < 0 ? fail(rc, message_out) : 0;
}

void msuv_timer_close(ms_object *timer) { timer_drop(ms_payload(timer)); }
```

- A timer is closed by `close()` or, if the program forgets, by its drop. Either way libuv finishes with the memory before `on_closed` frees it, and the loop's drop closes anything still open, so nothing leaks.
- `msuv_loop_close` (not shown) does what `loop_drop` does and reports `uv_loop_close` errors.
- To keep other tasks running while libuv waits, there are two options:
  - run the loop in a worker;
  - run `uv_run` on a shim thread and deliver each event with `ms_post`, holding the callback with `ms_fn_hold`. The callbacks then run as tasks and may wait, which is how Node sits on libuv.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt-abi/include/ms_abi.h` | the header above | C and C++ test archives compiled per platform in CI |
| `crates/ms-rt` | `ms_*_v1` functions: strings, lists, objects, `ms_fn` with hold, `ms_call` with guard and re-raise, `ms_post`/`ms_call_wait` over a new inbox message with a queue limit, native lane with cancel, multi-socket wait, stop hooks, isolate state | unit tests per group; foreign-thread, fault-in-callback, cancel-during-blocking and stop-hook tests per platform |
| `crates/ms-check` | user extern types per the signature table; user `extern type`; function arguments escape; `message` error case | conformance accept and reject cases with exact diagnostics |
| `crates/ms-lower`, `crates/ms-clif` | `ms_fn` wrapping and one invoke thunk per function type; integer extension; pre-filled `out`/`code_out`/`message_out`; re-raise after an extern returns | ABI round-trip test with every type, both backends |
| `crates/ms-clif/src/link` | Windows: embed `iphlpapi`, `psapi`, `ole32` for libuv | Windows libuv example links |
| `documentation/core-language/functions/native-functions.md` | rewritten around the header | `make docs`, example checks |
| `examples/libuv-timer` | the worked example | CI builds it against a pinned libuv |
| parser, grammar, formatter, LSP, `stdlib/*.ms` | unchanged (no syntax) | |

## Alternatives

- **Do nothing.** Scalar-only libraries work. libuv cannot be bound: there are no handles, no callbacks, and no error text.
- **Pointers and raw memory in Manuscript.** Rejected: "keep c things in c and ms things in ms".
- **Records and maps in the header.** Records and maps would need generated layouts or accessors per type, and a shim would depend on compiler layouts. A Manuscript wrapper converts them to the signature types instead, which keeps the header fixed.
- **Calling closure code directly from C.** It follows the C ABI only for scalars; `ms_call` with `ms_value` arguments works for every signature, and kind checks make a mismatch a fault, not memory corruption.
- **Pull events only, no callbacks.** Rejected: "the interop needs to be complete". It cannot answer a callback (comparators, SQLite's busy handler) or accept calls from foreign threads.

## Staging and verification

Each stage lands green on Linux, macOS and Windows; no platform skips.

1. **Groups 1 to 7:** versioning, status codes, strings, values, lists, objects, errors and faults.
   - Gate: a C test archive round-trips every signature type on both backends, and an object's drop runs exactly once.
2. **Groups 8 to 11:** functions, blocking work, sockets, stop hooks, isolate state.
   - Gate: same-thread calls of each kind work.
   - Gate: a callback fault reaches a worker's `join`, and a callback that waits faults with its message.
   - Gate: 10,000 posts from a C thread all run, and `ms_call_wait` returns results.
   - Gate: cancelling during `ms_blocking` runs `cancel` and returns after `work`.
   - Gate: SIGINT to a program blocked in C exits 130 through its hook.
3. **libuv:** timer and TCP echo server, with the loop on the main isolate, in a worker, and on a shim thread using `ms_post`.
   - Gate: all variants run on all three platforms, and the leak check is clean.
- Go/no-go after stage 2: if `ms_call` needs changes to the fault or task machinery beyond the guard, stop and report.
- Checks per stage: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo nextest run --workspace`, `make verify`; `make verify-full` before stage 3 merges.

## Non-goals

- Dynamic loading: static musl executables cannot `dlopen` (`proposals/bundled-linker.md`).
- Embedding Manuscript in a C program.
- Generating shims from C headers.

## Open questions

1. **Building shims.** Shims and libraries must target musl on Linux and the mingw UCRT on Windows, and `ms` bundles no C compiler.
   - Recommended: document the commands per platform for now (for example `zig cc`, or clang with a musl sysroot), and decide on bundling a compiler separately.
   - Alternative: bundle clang as `ms cc` now.
2. **Callbacks that wait.** Recommended: `ms_call` faults if the callback would wait, and `ms_post` callbacks may wait. Alternative: allow waiting and make re-entrancy the shim's responsibility.
3. **Zero-copy buffers.** Recommended: copy now, and add native-owned `Bytes` only if a benchmark shows copies matter. Alternative: design it now.
