# ms-rt ABI (version 1)

Contract between generated code (`ms-clif`) and the native runtime (`ms-rt`).
Machine-checked constants live in `crates/ms-rt-abi/src/lib.rs`; read offsets
from there. This file is the prose contract plus the symbol catalogue. The Go
runtime in `pkg/runtime` remains the behavioral oracle.

## Changes since publication

_(Newest first. Anything that alters a layout, signature or ownership rule is
recorded here before it is committed.)_

- v1 initial publication.

## 1. Conventions

- 64-bit targets only (x86_64 and aarch64 Linux first). All functions are
  `extern "C"`, named `msrt_<module>_<name>`. Data symbols are `msrt_*` too.
- Scalar mapping: `Int` = `i64`, `Float` = `f64`, `Bool` = `u8` (0 or 1; callers
  zero-extend, the runtime treats any non-zero as true on input and returns 0/1),
  `Unit` is never passed. Every object type (`String`, `Bytes`, `List`, `Map`,
  `Set`, builders, closures, records, alternatives) is a pointer to its header.
- Nothing wider than a register is passed or returned by value. There are no
  struct-by-value parameters or results anywhere in the ABI.
- **Optional parameters.** `Optional[Int|Float|Bool]` is flattened into two
  parameters `has: u8, value: i64|f64|u8` (value ignored when `has == 0`).
  `Optional[<object>]` is a nullable pointer.
- **Optional results.**
  - Scalar payloads: the function returns `present: u8` and writes the payload
    through a trailing `out: *mut i64|f64|u8` only when present.
  - Object payloads (`String`, `Bytes`, `List`...): nullable owned pointer.
  - Generic element payloads (list `pop`, `first`, ...): returns `present: u8` and
    moves the element into the slot `out: *mut u8` (`desc.size` bytes).
- **Fallible results (`Result[T, XError]`).** The function returns a `status: u8`
  (`STATUS_OK = 0`, otherwise the error case, see `ms-rt-abi`) and writes the ok
  value through a trailing `out` pointer only on success. The compiler builds the
  `Result`/error alternative; the runtime never constructs alternatives.
  Errors carrying messages (`StringError.Failed`) are not produced by the runtime.
- **Ownership.** Arguments are **borrowed** unless the signature below is marked
  _consumes_. Results are **owned (+1)**. Consuming parameters are exactly:
  element/key/value slots given to *store* operations (`append`, `insert`, `set`,
  `prepend`, `fill`, `splice` replacement items are copied with retain instead,
  `map_add`, `set_add`, `listbuilder_append`, ...) and `msrt_cleanup_*` arguments as
  documented. Search operations (`contains`, `index_of`, `map_get`, `map_remove`,
  ...) borrow the probe slot. Element values written to an `out` slot are owned.
- **Slot pointers.** Generic operations pass an element, key or value as a pointer
  to a slot of `desc.size` bytes with `desc.align` alignment (a stack slot is
  fine). For pointer-like types the slot contains the object pointer.
- **Faults.** Every runtime check failure calls the fault path and never returns.
  Message text equals the Go runtime's.
- **Null.** `msrt_retain` and `msrt_release` accept null (Optional `none`).
  Everything else requires non-null object pointers.
- Sizes and indices are `i64` (Int), never `usize`, at the boundary.

## 2. Objects, reference counting, drop

```text
Obj { rc: usize @0, drop: fn(*mut Obj) @8 }          16 bytes, object pointers point here
```

- New objects start with `rc = 1` (the creator's reference).
- Retain: `rc += 1` (non-atomic). Release: `rc -= 1; if rc == 0 { call drop }`.
- Static and literal objects (string literals, constant lists) live in writable
  data with `rc = STATIC_RC` (2^62) and a valid `drop`; count updates are harmless.
- `drop(obj)` must release every child it owns and then `msrt_free(obj)`. Freed
  memory must not be touched afterwards. Generated record drops follow the same
  rule; the runtime exports `msrt_drop_string`, `msrt_drop_list`, `msrt_drop_map`,
  `msrt_drop_strbuilder` for header initialisation of static objects.
- Deep structures: `msrt_release` and `msrt_drop_slow` bound recursion. Past a
  nesting depth of 4096 dropping, further zero-count objects are queued on an
  intrusive list (reusing `rc` as the link) and dropped iteratively once the outer
  drop returns. Drop functions therefore must tolerate being deferred and must not
  assume the child is freed when `msrt_release(child)` returns.
- Cycles are never collected (documented leak).
- Non-atomic counts: generated code and runtime run on one thread. The runtime
  runs `main` on a dedicated big-stack thread (see section 9); user code never
  runs on another thread.

### Allocator

`msrt_alloc(size: usize) -> *mut u8` returns uninitialised memory, 16-byte
aligned, never null (out of memory is a fault). `msrt_alloc_zeroed(size)`,
`msrt_realloc(ptr, new_size)`, `msrt_free(ptr)` (no size argument; the allocator
finds the size class from the pointer). Sizes up to 2048 bytes use a size-class
free list (16-byte steps up to 128, then four steps per doubling); larger blocks go to
the system allocator. Single threaded, no locking.

## 3. String and Bytes

```text
StrObj { hdr @0, len: usize @16, scalars: usize @24, data[len] @32, NUL }
```

- `len` is the UTF-8 byte length; `scalars` is the Unicode scalar count or
  `SCALARS_UNKNOWN` (`usize::MAX`), filled lazily by `msrt_string_length`. A literal
  may be emitted with the exact count (ASCII: `len`) or unknown.
- Immutable once created, except for the lazy `scalars` cache and `rc`.
- A NUL byte follows the data for C interop; it is not part of `len`.
- Indices and lengths at the language level count scalars; `byte_length` is `len`.
- `Bytes` has the same layout (`scalars` unused, 0) but its own `desc`.
- Text may in principle contain invalid UTF-8 only if the compiler produced it;
  the runtime tolerates it (invalid bytes decode as U+FFFD of width 1, like Go).
- Empty string: allocated like any other; `msrt_string_empty()` returns a static.

## 4. Type and element descriptors

```text
TypeDesc { size: u32 @0, align: u32 @4, kind: u32 @8, reserved: u32 @12,
           drop @16, retain @24, eq @32, hash @40 }       48 bytes, 8-aligned, read-only
```

One static descriptor per distinct slot type. The runtime exports builtins:
`msrt_desc_int`, `msrt_desc_float`, `msrt_desc_bool`, `msrt_desc_string`,
`msrt_desc_bytes`. `kind` selects built-in behavior (see `KIND_*`):

| kind | slot | drop / retain | equality | hash |
| --- | --- | --- | --- | --- |
| `INT` | i64 | none | `==` | mixed |
| `FLOAT` | f64 | none | IEEE (`NaN != NaN`, `0.0 == -0.0`) | none (Float is not Hashable) |
| `BOOL` | u8 | none | `==` | mixed |
| `STRING` | non-null `StrObj*` | release / retain | content | content |
| `BYTES` | non-null `StrObj*` | release / retain | content | content |
| `PTR` | nullable object pointer | release / retain (null safe) | `eq` if present else identity | `hash` if present else address |
| `POD` | `size` bytes of plain bits | none | `eq` if present else `memcmp` | `hash` if present else byte hash |
| `CUSTOM` | `size` bytes | `drop` / `retain` fn (None = nothing owned) | `eq` | `hash` |

Function pointer contracts: `drop(slot)`, `retain(slot)` (called after a bitwise
copy so the copy owns its own references), `eq(a, b) -> u8`, `hash(slot) -> i64`.
Equal values must hash equally; hashes are deterministic across runs.
Generated `eq` functions of recursive types call `msrt_eq_enter(a, b)`
before descending (returns 0 when the pair is already under comparison, which
means "assume equal", terminating cyclic data) and `msrt_eq_leave(a, b)` after.
`msrt_hash_int`, `msrt_hash_bytes`, `msrt_hash_combine` build record hashes.

## 5. Collections

### List and ListBuilder

```text
ListObj { hdr @0, len @16, cap @24, data @32, desc @40, flags @48 }   56 bytes
```

Elements are stored inline at `data + i * desc.size`; `data` is null when
`cap == 0`. The element descriptor travels with the object so the generic
operations need no descriptor argument. `ListBuilder[T]` is the same object;
`freeze` sets `FLAG_SEALED` on it and returns it (+1) without copying; later
builder appends fault with `builder is sealed`. Plain `List.append` ignores the flag.

- Negative indices count from the end where the Go runtime allows it (`get`, `set`,
  `remove`, `insert`, `slice`); `splice`, `fill`, `copy_within` take exact bounds.
- Iteration protocol for `for x in list`: capture `n = len` at loop entry; each
  iteration re-read `data` and `len` and stop when `i >= min(n, len)`. Appends do
  not extend the loop; element writes are visible. (Differs from Go only when the
  body removes elements: Go keeps iterating the stale tail, the runtime stops.)
- Higher-order operations (`map`, `filter`, `fold`, `find`, `some`, `every`,
  `count`, `for_each`, `group_by`, `flat_map`, `find_*`) are **lowered by the
  compiler** to loops over `len`/`data`, so closures are inlined and are not a
  runtime ABI. The runtime provides `msrt_list_sort` (with a comparator thunk) and
  everything that needs no user code.

### Map, Set and builders

```text
MapObj { hdr, len @16, slots, used, cap, index, mask, kdesc, vdesc, flags, key_off, val_off, stride }
```

Insertion ordered (observable: `keys`, `values`, `entries`, iteration, formatting).
`Set[T]` is a `MapObj` with `vdesc == null`. Only `len @16` is a stable
generated-code field. Replacement keeps the original key and position. Removal
leaves a hole that iteration skips; storage compacts when more than half of the
slots are holes (never during an iteration by index, see below).

- Iteration: `msrt_map_keys`/`msrt_map_values`/`msrt_set_values` return fresh
  lists (a snapshot, matching Go's "callbacks traverse a snapshot"). For
  allocation-free scans use `msrt_map_slot_count` and `msrt_map_entry_at(map, i, key_out, val_out)`
  (returns 0 for holes; call retains the entry). Do not mutate during a slot scan.
- Float keys are rejected by the language (no `Hashable`); `msrt_desc_float` still supports `eq`.

### StringBuilder / BytesBuilder

`StrBuilderObj { hdr, buf: *mut StrObj, cap, flags }`. `append` grows `buf`
geometrically; `freeze` seals and returns `buf` (+1, no copy). Repeated `freeze`
returns the same string. Appending after freeze faults with `builder is sealed`.
`BytesBuilder` is the same object; its `freeze` result has the Bytes meaning.

## 6. Optional, Result, closures, interfaces

- `Optional[T]` with pointer-like `T`: the pointer, null = `none`. `Optional[Int]`:
  `OptInt { present: u8 @0, value: i64 @8 }` (16 bytes); `Optional[Float]` likewise;
  `Optional[Bool]` is `{ present: u8 @0, value: u8 @1 }`. Optional of an
  `Optional` or of a zero-sized value is compiler-defined (not used by the runtime).
- `Result[T, E]`: compiler-defined layout (tag plus payload). Runtime functions only
  use the status/out protocol of section 1.
- Closures: `Closure { hdr, code @16, captured values @24.. }`. `code` has the C
  signature `fn(closure: *mut Closure, args...) -> ret`. The runtime calls closures
  only through the sort comparator thunk below.
- Interface values: `{ data: *mut Obj, vtable }` 16 bytes, passed as two
  registers by generated code; the runtime never sees one.

## 7. Faults

```text
msrt_fault(msg: *const u8, len: usize) -> !          message bytes are copied
msrt_fault_string(msg: *mut StrObj) -> !
msrt_fault_depth() -> !                              "call depth limit exceeded (200000 nested calls)"
msrt_index_fault(index: i64, length: i64) -> !       "index I out of range for length N; pass a default: get(index:, default: ...)"
msrt_fault_unwrap_none() -> !   msrt_fault_result_get() -> !   msrt_fault_result_err() -> !
msrt_fault_int_overflow() -> !  msrt_fault_div_zero() -> !  msrt_fault_rem_zero() -> !  msrt_fault_div_overflow(a, b) -> !
```

A fault (1) captures the innermost source frames by walking frame pointers and
resolving return addresses through the tables (`FuncEntry`/`LineEntry`), at most 32
frames then `  ... outer frames omitted`; (2) runs the registered cleanup actions
innermost first (a fault inside a cleanup becomes a `cleanup fault: <message>` line
and the walk continues); (3) flushes stdout, writes to stderr

```text
<message>
  at <file>:<line> in <function>        (innermost first)
  ... outer frames omitted              (only when truncated)
cleanup fault: <message>                (one per secondary fault)
```

and exits with status 70. Generated code must be compiled with frame pointers
(rbp / x29 chains) and must not use tail calls that drop frames. Frames whose
return address is not inside `FuncTable` are skipped (runtime frames).

**Call depth.** `msrt_call_depth: i64` (data symbol). Functions in a recursive
cycle do `depth += 1; if depth > 200000 { msrt_fault_depth() }` on entry and
`depth -= 1` on every normal return. Non-recursive call graphs skip it.
**Cancellation.** `msrt_cancel_flag: u8` (data symbol) becomes non-zero (the signal
number) after SIGINT/SIGTERM unless shielded. Loops and calls poll it with a relaxed
load and call `msrt_cancelled() -> !` when set, which unwinds cleanups and exits
130 (SIGINT) or 143 (SIGTERM). A second stop request, or 30 s after the first, prints
`incomplete cleanup: <reason>` and exits 70 without further cleanup.

**Cleanup stack (`with`).** `msrt_cleanup_push(f: fn(arg: *mut u8), arg: *mut u8) -> usize`
registers `f(arg)` and returns a handle; the pair is owned by the stack until run.
`msrt_cleanup_run(handle)` runs and removes that action now (normal scope exit;
actions registered after it that are still pending run first, innermost to outermost).
On a fault, remaining actions run LIFO, shielded from cancellation. A fault raised
while an action runs on the normal path is an ordinary primary fault.

## 8. Naming scheme and catalogue

`msrt_<module>_<name>`; modules: `rc`, `mem`, `fault`, `cleanup`, `int`, `float`,
`bool`, `numbers`, `string`, `bytes`, `list`, `map`, `set`, `listbuilder`,
`mapbuilder`, `setbuilder`, `strbuilder`, `bytesbuilder`, `io`, `process`, `eq`,
`hash`, `profile`. Future crates (`ms-std-fs`, `ms-std-json`, ...) use their
module name as the prefix and are linked only when imported; they depend on
`ms-rt-abi` for layouts and call `msrt_*` for allocation and faults. The
authoritative list of exported symbols is the `#[no_mangle]` items in `ms-rt/src`
(`cargo doc -p ms-rt`); this section lists the groups. Language-level operation
names match `pkg/stdlib/*.ms` (`String.split` is `msrt_string_split`).

Argument order: receiver first, then declared parameters, then flattened
optionals in declaration order, then the `out` pointer last.

Inline fast paths generated code may open-code (all are part of the ABI):

1. Retain: `if p != null { p.rc += 1 }` (static objects need no check).
2. Release: `if p != null { p.rc -= 1; if p.rc == 0 { msrt_drop_slow(p) } }`.
3. List index load `xs[i]`: `if (i as u64) < len { *(data + i * desc.size) }`, with
   retain of pointer elements; otherwise call the slow path (negative index,
   default or `msrt_index_fault`). Same for index store (release old, consume new).
4. List push: `if len < cap { store at data + len*size; len += 1 } else msrt_list_push*`.
5. String byte length (`len @16`), Bytes length, List length (`len @16`), Map/Set length (`len @16`).
6. Call-depth counter and cancel-flag polling (section 7).
7. `Int` checked arithmetic (use hardware overflow flags, call `msrt_fault_int_overflow`).
8. `Optional` presence tests and payload loads; `ASCII` single-byte string equality is not inlined.

## 9. Process entry, I/O, profiler

`msrt_start(main_fn: extern "C" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8) -> i32`
is called from the C `main` the compiler emits (`return msrt_start(...)`): it
installs the tables, signal handlers and the profiler (when requested), runs
`main_fn` on a dedicated thread with a 1 GiB stack (so the 200,000-call limit is
reachable), checks the exit code range (`0..=125`, else the Go fault message), flushes
stdout and returns the process status (also 130/143 after a stop request). `msrt_args() -> *mut ListObj`
returns a fresh `List[String]` of the program arguments (argv[1..]).

`msrt_io_write_stdout(s)`, `msrt_io_write_stderr(s)`, `msrt_io_flush()`: stdout is
buffered (64 KiB; line buffered on a terminal) and flushed before any stderr
write, on fault, on exit and by `msrt_io_flush`. `msrt_process_exit(code: i64) -> !`
flushes and exits immediately (no cleanup).

### Symbol table (`Tables`)

The compiler emits read-only data and passes its address to `msrt_start`:

```text
Tables { abi_version: u32, reserved: u32, funcs, func_count, lines, line_count, strings, strings_len }
FuncEntry { addr: usize, size: u32, name_off: u32, file_off: u32, line: u32 }    24 bytes, sorted by addr
LineEntry { pc: usize, line: u32, file_off: u32 }                                16 bytes, sorted by pc
```

`name_off`/`file_off` index NUL-terminated strings in `strings`. `addr` are
link-time addresses (relocated by the linker; the runtime does not slide them).
`pc` is a return address; `file_off == u32::MAX` means "the function's file".
Function names are the names shown in fault traces (`inner`, `Point.norm`,
`main.lambda2`). Only source functions belong in `FuncTable`.

### Profiler

`MS_PROFILE=<path>` enables sampling for the whole run. Options:
`MS_PROFILE_HZ` (default 1000, 1..=10000), `MS_PERF_MAP=1` (also write
`/tmp/perf-<pid>.map`; `ms profile` symlinks or copies it to the name `perf` wants).
`ITIMER_PROF` raises SIGPROF; the handler is async-signal-safe: it reads the
interrupted pc and frame pointer from `ucontext`, walks the frame-pointer chain
within the stack bounds recorded at start (at most 128 frames) and stores raw pcs
in a preallocated ring of 65,536 samples (no allocation, overflow drops and counts).
At exit (normal, fault, or stop) the runtime resolves pcs through `FuncTable` and
writes **folded stacks**, one line per distinct stack, outermost first:

```text
main;work;inner 412
main;work 17
[runtime];<unknown> 3
```

(unresolved frames are `0x<hex>`, runtime frames outside the table collapse to `[runtime]`.)
`ms profile <program> [args]` sets `MS_PROFILE` to a temp file, runs the native
program, converts the folded file to its pprof output and, with `--perf-map`, sets
`MS_PERF_MAP=1` so `perf record -g ./program` can symbolize frames; the compiler's
frame pointers make `perf record --call-graph fp` work with or without the sampler.
Samples report how many dropped (last line `# dropped <n>`).

## 10. Fast-path summary the code generator should specialise

Per-type specialisations exist for `Int` and pointer elements where a call per element
would be wasteful: `msrt_list_push_i64`, `msrt_list_push_ptr` (consumes), `msrt_list_get_i64`,
`msrt_map_get_i64`, `msrt_map_add_i64_*` (planned; see catalogue in `ms-rt/src`).
