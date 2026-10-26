# ms-rt ABI (version 3)

Contract between generated code (`ms-clif`) and the native runtime (`ms-rt`).
Machine-checked constants live in `crates/ms-rt-abi/src/lib.rs`; read offsets
from there. This file is the prose contract plus the symbol catalogue. Source-level
behavior is checked by the frozen conformance corpus in `tests/conformance/`;
the earlier Go runtime has been removed.

## Changes since publication

_(Newest first. Anything that alters a layout, signature or ownership rule is
recorded here before it is committed.)_

- **extern (ABI_VERSION unchanged).** `extern def` declarations call a native symbol of the same name under the conventions below, for scalars, borrowed `String` arguments, and `Int`/`Float`/`Bool`/`String`/`Unit` results, or `Result[T, E]` as a `u8` status (`n` names the `n`th case of a payload-free `E`) plus `out` (`documentation/core-language/functions/native-functions.md`). `crates/ms-rt-abi/include/ms_abi.h` is the C view of `StrVal` for such natives; `msrt_string_from_bytes` is how they build owned string results.
- **v3 (collection creator evidence).** `MapVal` appends a static key descriptor pointer (56 bytes).
  `msrt_map_stamp` captures creator-module equality and hashing without replacing existing evidence;
  clone, clear, and derived Set operations retain it. Descriptor-neutral native maps keep a null
  pointer and use the supplied builtin descriptor.
- **v2.2 (stdlib natives, ABI_VERSION unchanged).** Standard-library natives that need no runtime state live in `ms-std-<module>`
  crates (rlibs linked into `libms_native.a` with `ms-rt`) and are named `msstd_<module>_<name>`; the argument and ownership rules above apply.
  `ms-std-math` exports `@std/math` (`f64`/`i64` by value; `Bool` as `u8`; results come from the host libm and may differ from Go in the last bit). `ms-rt` gains
  `msrt_numbers_parse_int/parse_float/error_message`, `msrt_float_to_precision/to_exponential/to_fixed` (string `out`; a digit count out of range faults),
  `msrt_float_truncate_to_int` (present flag + `out`) and `msrt_float_compare`/`msrt_int_compare`.
- **v2.7 (`ms-std-fs` watchers).** `msstd_fs_watch` (polling, snapshot comparison every interval) and `msstd_fs_watch_native` (inotify on Linux, kqueue plus snapshot comparison
  on macOS, `ReadDirectoryChangesW` on Windows) return a refcounted watcher handle; `msstd_fs_watch_next` waits in 50 ms slices (cancellable)
  and returns a `List[FileEvent]` (`kind` is `rename` or `change`); a native watcher returns one event per call, a polling watcher
  every difference sorted by path. `STATUS_CLOSED` after `msstd_fs_watch_close`, `STATUS_LIMIT_EXCEEDED` on overflow with policy `error`.
  No worker thread: events are read from the kernel inside `next`, so the queue is bounded by the kernel buffer plus `max_events`.
- **v2.6 (`ms-std-fs`).** File handles are the `@std/io` stream handle (`msstd_fs_file_open`; `reader()`/`writer()` reuse
  `msstd_io_*`), directory cursors and scoped temporary directories are their own refcounted handles (`msstd_fs_directory_*`,
  `msstd_fs_temporary_*`; `close` is idempotent and a temporary's `close` reports removal failures). `msstd_fs_open_flags` maps a mode string
  to host flags. `msstd_fs_glob` returns a `List[String]`; `msstd_fs_glob_entries` returns parallel `paths`/`names` string lists plus a flag
  byte per entry. `msstd_fs_copy` takes option bits (1 recursive, 2 replace, 4 error_on_exists, 8 dereference, 16 preserve, 32 verbatim), a
  clone mode string and entry/byte budgets (`i64::MAX` = unlimited). Callbacks are `extern "C-unwind"` thunks with a captured `env`: strings
  passed to them are borrowed for the call (the runtime releases its copies afterwards), `copy`'s returns non-zero to keep an entry and
  `glob_entries`' returns non-zero to exclude it. `msstd_fs_constants` returns the open-flag and mode constants as parallel name/value lists.
  Glob matching lives in `ms-std-path::glob` (shared with `@std/fs`) (braces, extglobs, `**`, and dotfile rules).
- **v2.5 (`ms-std-process`).** `msstd_process_*` covers process control and child processes. `STATUS_TIMEOUT` (13) and `STATUS_OUTPUT_LIMIT` (14)
  join the table for `CommandError`. `Map[String, String]` crosses as two parallel string lists (`environment`, `replace`). `command_run` takes
  the arguments, input bytes, optional limit and optional timeout and returns `CommandOut` (exit code, stdout, stderr); `command_spawn` returns a
  refcounted child handle whose three pipes are `@std/io` stream handles (`subprocess_stream`, each call adds a reference). Children start in their
  own process group and every wait polls in short slices so a pending cancellation kills the tree before unwinding. `ms-rt` adds `msrt_start_nanos`
  (origin of `uptime`) and `msrt_argv` (whole argv). `watch_signals` is `msstd_process_watch_signals`/`signal_next`/`signal_close`: each observer owns a pipe fed by a chained signal handler (the runtime's SIGINT/SIGTERM cancellation still runs). `memory_usage` fills `MemoryOut`; `heap_used` and `heap_total` come from the new `msrt_heap_stats` (small-block heap only), `resident` from `/proc/self/statm`.
- **v2.4 (`ms-std-fs`, `ms-std-io`).** `msstd_fs_*` are the path-based `@std/fs` operations and `msstd_io_*` the host streams of `@std/io`.
  Paths are strings; fallible calls return `STATUS_*` (`NOT_FOUND`, `ALREADY_EXISTS`, `NOT_EMPTY`, `PERMISSION_DENIED`, `UNSUPPORTED`,
  `CLOSED`, `FAILED`, `UNAVAILABLE`, `NONE` join the status table) and write `out` only on success. `FAILED` carries Go's `*PathError`
  text, read with `msstd_fs_failure_message` / `msstd_io_failure_message` until the next fallible call. Optional limits are a present
  flag plus an `i64`. `FileInfo` is flattened to `InfoOut`, filesystem status to `FsOut`; `list` returns names plus one flag byte per
  entry (bit 0 directory, bit 1 symlink). Streams are refcounted `Handle<Stream>` objects (`Obj` header, then the value); reads and writes
  poll in 50 ms slices so cancellation interrupts them. `STATUS_NONE` from `read`/`read_line` means end of stream. Generic `io.copy`,
  `read_all` and `read_line` over user-defined `ReadStream`s stay compiler-lowered.
- **v2.3 (`ms-std-time`, `ms_rt::glue`).** `msstd_time_*` covers `@std/time`. `Duration` is an `i64` of nanoseconds by value.
  `Timestamp` is `repr(C) { seconds: i64, nanos: i64 }` and `Instant` is `repr(C) { domain: u64, tick: i64 }`; both are passed by pointer
  and returned through a trailing `out`. `msstd_time_clock_now` uses domain 1 (the process monotonic clock); `Calendar` is returned as
  `CalendarOut` (ten `i64` fields in declaration order, then an owned zone-name string). Fallible calls return `STATUS_*` codes (`TimeError`
  maps `InvalidInput`/`OutOfRange`/`InvalidData` to the numbers codes; `Closed` is never produced natively). Zones come from the bundled
  IANA data (`jiff-tzdb`), `Local` follows `TZ` then `/etc/localtime`. `ms_rt::glue` is the shared glue (read/build strings, faults, cancellation).
- **v2 (value semantics).** The owner adopted value semantics (DESIGN.md decisions 1-2).
  Only `Shared` boxes (internal today, used for builder handles; the source type `Shared[T]` is planned) and closures keep an `Obj` header and a count.
  `String` is a two-word owned `StrVal` (`{ptr, tagged}`) over immutable bytes (section 3).
  `List`, `Bytes`, `Map`, `Set`, `StringBuilder` are **owned header-less values**
  (`VecVal` = `{ptr, len, cap}`, `MapVal` = six words at v2, seven since v3) living in the owner's slot;
  runtime operations take a **pointer to the value** (borrowed, or `&mut` for `var`
  receivers, mutators return nothing) and write constructed values through an `out`
  pointer. Descriptors are no longer stored in the value: every generic operation takes
  the element descriptor(s) explicitly. `TypeDesc` gained `inner0/inner1`, `copy`
  (replaces `retain`) and kinds `LIST/MAP/SET/SHARED`; `ListObj`, `MapObj`,
  `StrBuilderObj`, `FLAG_SEALED` were removed (builders are the collections
  themselves; `build` is a move; there is no "builder is sealed" fault).
  Clone becomes explicit `msrt_list_copy` / `msrt_slot_copy`. The sections below
  describe v2 only.
- **v2.1 (implemented runtime, `ABI_VERSION` 2).** Everything below is implemented and tested in `ms-rt`;
  `SYMBOLS.md` lists every exported symbol with its Rust signature. It is kept by hand; the `runtime_symbol_catalogue_matches_archive` test fails when it and the runtime archive disagree, and `stdlib/bindings.json` (`runtime_symbols`) names the symbol of each native function.
  - Strings: owned, immutable, uniquely owned buffers; empty and one-ASCII-byte results are static strings (tag `10`).
    The scalar count of the long string last measured is cached in a one-entry hint with a position for sequential indexing.
  - Optional/fallible conventions as in section 1: `Optional[Int]` result = `u8` present + `out: *mut i64`; `Optional[String]` = `OptStr { value: StrVal }` (16 bytes; none is a static empty string with a null `ptr`) through `out`, or a `present: u8` result with `out: *mut StrVal`
    (`bytes_decode_utf8`, `split_next`); `Result` = `status: u8` with `out` last; optional **parameters** flatten to `has_x: u8, x`
    (borrowed `Optional[String]` parameters flatten the same way, `has: u8, value: *const StrVal`, e.g. `msrt_string_get(s, index, has_default, default, out)`).
  - Lists: `msrt_list_*` take `(receiver*, desc*, ...)`. Language `drop(count)` is `msrt_list_drop_n` (`msrt_list_drop` releases the value);
    `append` is `msrt_list_push`; `prepend/insert/set` consume the element slot; `fill` borrows and copies its value; `splice` and `extend`
    consume the replacement list; `concat`, `slice`, `take`, `drop_n`, `reversed`, `sorted`, `distinct`, `flatten`, `to_set`, `filled`,
    `range`, `range_by`, `keys`, `join` build fresh owned results through `out`. Sorting is stable merge sort with the comparator thunk
    `extern "C-unwind" fn(env: *mut u8, a: *const u8, b: *const u8) -> i64` (negative = before); `env` is the closure the compiler passes.
  - Bytes/BytesBuilder/StringBuilder share `VecVal`; `msrt_bytes_append/extend`, `msrt_strbuilder_append`; `msrt_strbuilder_freeze` **consumes** the builder.
  - Maps/Sets (`msrt_map_*`, `msrt_set_*`): insertion ordered; `msrt_map_add` consumes key and value (replacing keeps the original position),
    `msrt_map_get_ptr` returns a borrowed value pointer or null, `msrt_map_get` copies; set algebra builds fresh sets in left-operand order.
    A set is a map with a null value descriptor and null value slot pointers.
  - `msrt_start(main_fn, tables, argc, argv)`: `main_fn` is `extern "C-unwind" fn() -> i64` (same machine ABI as `"C"`); runs on a 1 GiB mmap stack with a
    guard page; SIGINT/SIGTERM set the cancel flag; second request or 30 s later prints `incomplete cleanup: ...` and exits 67.
  - Profiler as in section 9 (`MS_PROFILE`, `MS_PROFILE_HZ`, `MS_PERF_MAP`); function tables resolve names, frames outside the table collapse to `[runtime]`.
  - `msrt_fault_destructure(names, elements)` raises the destructuring length mismatch fault.
  - The static library is built with `panic = "abort"`; it still exports a stub `rust_eh_personality` so `C-unwind` symbols link.
- v1 initial publication (reference-counted collections; superseded).

## 1. Conventions

- 64-bit targets only (x86_64 and aarch64 Linux first). All functions are
  `extern "C"` (declared `C-unwind` in Rust so tests can intercept faults; the ABI
  is identical), named `msrt_<module>_<name>`. Data symbols are `msrt_*` too.
- Scalars: `Int` = `i64`, `Float` = `f64`, `Bool` = `u8` (0/1), `Unit` is never passed.
- **No struct by value, ever.** Refcounted objects are passed as a pointer to the
  header. Owned aggregates (`String`, `List`, `Bytes`, `Map`, `Set`,
  `StringBuilder`) are passed as a **pointer to the value** (`*const StrVal` / `*const VecVal` /
  `*const MapVal` = borrowed read; `*mut` = `var` receiver, mutated in place).
  Constructed aggregates are returned through a trailing `out: *mut StrVal|VecVal|MapVal`
  (uninitialised memory in the caller; the callee initialises it; the caller owns it).
- **Optional parameters.** `Optional[Int|Float|Bool]` is flattened into
  `has: u8, value: i64|f64|u8`. `Optional[<refcounted object>]` is a nullable pointer.
- **Optional results.** Scalar payload: return `present: u8`, payload through a
  trailing `out` pointer only when present. `String`: `present: u8` with `out: *mut StrVal`. Generic
  elements: return `present: u8`, element moved/copied into `out: *mut u8`.
- **Fallible results.** Return `status: u8` (`STATUS_OK = 0`, else the error case
  from `ms-rt-abi`) and write the ok value through the trailing `out` only on
  success. The compiler builds `Result` and the error alternative.
- **Ownership.**
  - Value arguments are **borrowed** (read, not consumed) unless marked _consumes_.
    Mutators (`push`, `insert`, `set`, `remove`, `map_add`, `sort_in_place`...) take
    `*mut` to the receiver, return nothing (Unit), and **consume** their element/key/value
    slot arguments (ownership moves into the collection; the compiler copies first if
    it still needs the value).
  - Probe slots of search operations (`contains`, `index_of`, `map_get`, `map_remove`...)
    are borrowed.
  - **Reads of elements** come in two forms: `*_at`/`*_ptr` return a *borrowed pointer into
    the container* (valid until the container is mutated or dropped; the checker's
    lexical borrow rules guarantee this), `*_get`/`*_copy` duplicate the element with the
    descriptor's `copy` into `out` (owned).
  - Constructed results (`out` values, returned strings) are **owned**.
  - Disjointness: a `*mut` receiver never aliases another argument (checker rule).
  - Consuming parameters: element/key/value slots of stores, and `drop` of owned values.
- **Slot pointers.** Generic operations pass an element, key or value as a pointer
  to a slot of `desc.size` bytes, `desc.align` aligned (stack slot is fine).
- **Descriptors are explicit**: every generic collection operation takes the
  element descriptor (`desc`) or key/value descriptors (`kdesc`, `vdesc`; sets pass
  `vdesc = null`) as arguments, right after the receiver pointer(s).
- **Faults** never return; messages are stable text.
- `msrt_retain`/`msrt_release` accept null. Everything else requires non-null.
- Sizes and indices are `i64` (Int) at the boundary.

## 2. Reference-counted objects (Shared, closures, handles) and drop

```text
Obj { rc: usize @0, drop: fn(*mut Obj) @8 }       16 bytes; pointers point here
```

`Shared` boxes (and planned `Weak[T]`), closures and runtime handle objects have a header. A `String` has no header
and no count (section 3). `rc` starts at 1; retain is
`rc += 1`; release is `rc -= 1; if rc == 0 { drop(obj) }`. Static and literal objects
live in writable data with `rc = STATIC_RC` (2^62). `drop(obj)` drops what the
object owns and then calls `msrt_free(obj)`. Deep ownership chains (linked lists,
trees) must not overflow the stack: `msrt_drop_slow` bounds drop nesting at 4096 and
queues further zero-count objects on an intrusive list (reusing `rc` as the link), drained
iteratively. Owned values (`List`, `Map`, records) are dropped through
`msrt_slot_drop(desc, slot)`; the runtime applies the same depth bounding there.
Cycles through `Shared` are never collected (documented leak).

### Allocator

`msrt_alloc(size) -> *mut u8` (16-aligned, uninitialised, never null: exhaustion is a
fault), `msrt_alloc_zeroed`, `msrt_realloc(ptr, new_size)`, `msrt_free(ptr)` (no size
argument). Blocks up to 2048 bytes come from size-class pages (16-byte steps to 128,
then four steps per doubling); larger blocks use the system allocator, rounded up to four
steps per doubling from 4 KiB to 16 MiB, and freed blocks in that range are kept in free
lists (up to 64 MiB) for reuse instead of returning to the system. No locking.

## 3. String

```text
StrVal { ptr @0, tagged: usize @8 }       String, 16 bytes
```

The top two bits of `tagged` say where the bytes are:

| top bits | kind | drop | copy |
| --- | --- | --- | --- |
| `00` | owned allocation starting at `ptr` | `msrt_str_free(ptr)` | `msrt_str_copy(ptr, tagged, out)` |
| `01` | inline: up to 15 bytes in the value itself | nothing | bitwise |
| `10` | static (literal, empty, one ASCII byte) | nothing | bitwise |
| `11` | view of another string's bytes | nothing | `msrt_str_copy(ptr, tagged, out)` |

For every kind but inline, `ptr` points at the UTF-8 bytes, a NUL follows them (not counted), and
`tagged & STR_LEN_MASK` is the byte length. An inline string keeps its length in bits 56–59 of
`tagged` (`STR_INLINE_LEN_SHIFT`) and its bytes in the value, little-endian from its address: the
whole `ptr` word, then the low 7 bytes of `tagged`; bytes past the length are zero. Its data
pointer is therefore the value's own address (`StrVal::data`). `msrt_str_copy` returns an inline
string when the copy fits, so copying a short string never allocates. A string is owned exactly when
`tagged < 1 << 62` (unsigned). `Optional[String]` uses the same two words, with None as `{0, STR_STATIC}`;
presence is `(ptr | (tagged ^ STR_STATIC)) != 0`, because an inline string can have a zero `ptr`
word. A view is only handed out where the source outlives it
unchanged: `trim`, `split` lists that the block reads only in place over a read-only parameter
(`msrt_string_split_view`), `for` loops over the keys or values of such a map
(`msrt_map_keys_view`, `msrt_map_values_view`). Language-level indices and lengths count Unicode
scalars; `byte_length` is the length. Invalid UTF-8 (only from a compiler bug) decodes as U+FFFD of
width 1. `msrt_string_empty(out)` writes a static.

## 4. Owned aggregates

```text
VecVal { ptr @0, len @8, cap @16 }                          List[T], Bytes, StringBuilder
MapVal { slots, index, len @16, used, cap, mask, desc }     Map[K,V], Set[T]; 56 bytes
```

- Empty lists have `ptr == null`, `cap == 0`. Elements are inline at `ptr + i * desc.size`.
- A value has one owner. Moving it is a bitwise copy of the 3/7 words (the source is dead).
  Dropping it: `msrt_list_drop(v, desc)` / `msrt_map_drop(v, kdesc, vdesc)`.
  `.copy()` is `msrt_list_copy` / `msrt_map_copy` (deep, through `desc.copy`).
- `Bytes` is a `VecVal` of `u8`; `BytesBuilder` is the same value, `build` is a move.
  `StringBuilder` is a `VecVal` of bytes; `msrt_strbuilder_freeze` copies into a String.
  `ListBuilder`, `MapBuilder`, `SetBuilder` are the collection values; `build` is a move.
- Negative indices count from the end where the Go runtime allows it (`get`, `set`,
  `remove`, `insert`, `slice`); `splice`, `fill`, `copy_within` take exact bounds.
- Iteration: `for x in xs` captures `n = len` at entry, reloads `ptr`/`len` each step
  and stops at `min(n, len)`. (The loop variable is a lexical borrow, so the body
  cannot mutate `xs` under value semantics; the rule only matters for `var` loops.)
- Higher-order methods (`map`, `filter`, `fold`, `find*`, `some`, `every`, `count`,
  `for_each`, `group_by`, `flat_map`) are lowered by the compiler to loops over
  `len`/`ptr`. The runtime provides `msrt_list_sort` (comparator thunk) and everything
  needing no user code.
- Maps/Sets are insertion ordered (observable via `keys`, `values`, `entries`,
  iteration, formatting). Replacing a value keeps the original key and position.
  Removal leaves a hole that scans skip; storage compacts when over half the slots
  are holes. Iterate allocation-free with `msrt_map_slot_count` and
  `msrt_map_entry_ptrs(map, kdesc, vdesc, i, key_out, val_out) -> u8` (borrowed
  pointers into the slot, 0 for holes); do not mutate during a scan (the lexical
  borrow rule forbids it). `msrt_map_keys`/`values` return fresh copies.
- Hashing is deterministic (no seed); order never depends on it.

## 5. Type and slot descriptors

```text
TypeDesc { size u32 @0, align u32 @4, kind u32 @8, _ @12, inner0 @16, inner1 @24,
           drop @32, copy @40, eq @48, hash @56 }          64 bytes, read-only
```

| kind | slot contents | drop / copy | equality | hash |
| --- | --- | --- | --- | --- |
| `INT` / `BOOL` | i64 / u8 | none / bitwise | `==` | mixed |
| `FLOAT` | f64 | none / bitwise | IEEE (`NaN != NaN`, `0.0 == -0.0`) | none |
| `STRING` | `StrVal` (16 bytes) | free / duplicate | content | content |
| `BYTES` | `VecVal` of u8 | free buffer / duplicate buffer | content | content |
| `SHARED` | nullable `Obj*` | release / retain | `eq` else identity | `hash` else address |
| `POD` | plain bits | none / `memcpy` | `eq` else `memcmp` | `hash` else bytes |
| `LIST` | `VecVal`, element `inner0` | recursive | element-wise | unsupported |
| `MAP` | `MapVal`, `inner0`/`inner1` | recursive | order independent | unsupported |
| `SET` | `MapVal`, `inner0` | recursive | order independent | unsupported |
| `CUSTOM` | records, alternatives... | `drop` / `copy` (None = bitwise) | `eq` | `hash` |

Function contracts: `drop(slot)`, `copy(src, dst)` (dst uninitialised), `eq(a, b) -> u8`,
`hash(slot) -> i64`. Equal values hash equally. Builtin descriptors the runtime exports:
`msrt_desc_int`, `msrt_desc_float`, `msrt_desc_float32`, `msrt_desc_bool`, `msrt_desc_string`,
`msrt_desc_bytes`. Generated `eq` of recursive types calls `msrt_eq_enter(a, b)`
before descending (0 means the pair is already being compared: assume equal) and
`msrt_eq_leave(a, b)` after. `msrt_hash_int`, `msrt_hash_bytes`, `msrt_hash_combine`
build record hashes. Generic helpers: `msrt_slot_drop`, `msrt_slot_copy`,
`msrt_slot_eq`, `msrt_slot_hash`.

## 6. Optional, Result, closures, interfaces

- `Optional[T]` of a refcounted pointer: the pointer, null = none. `Optional[Int]`:
  `OptInt { present u8 @0, value i64 @8 }` (16 bytes), `Optional[Float]` likewise,
  `Optional[Bool]` `{ present u8 @0, value u8 @1 }`. Optional of aggregates is compiler-defined.
- `Result[T, E]`: compiler-defined; the runtime only uses the status/out protocol.
- Closures: refcounted `Closure { hdr, code @16, captured @24.. }`; `code` is
  `fn(closure, args...)`. The runtime calls closures only via the sort thunk.
- Interface values: `{ data, vtable }`, two registers; the runtime never sees them.

## 7. Faults, cleanup, depth, cancellation

```text
msrt_fault(msg: *const u8, len: usize) -> !          message bytes are copied
msrt_fault_string(msg: *const StrVal) -> !
msrt_fault_depth() -> !                              "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead"
msrt_index_fault(index: i64, length: i64) -> !       "index I out of range for length N; pass a default: get(index:, default: ...)"
msrt_fault_unwrap_none() -> !   msrt_fault_result_get() -> !   msrt_fault_result_err() -> !
msrt_fault_int_overflow() -> !  msrt_fault_div_zero() -> !  msrt_fault_rem_zero() -> !  msrt_fault_div_overflow(a, b) -> !
```

A fault (1) captures the innermost source frames by walking frame pointers and
resolving return addresses through the tables (at most 32, then
`  ... outer frames omitted`); (2) runs registered cleanup actions LIFO (a fault inside
one becomes a `cleanup fault: <message>` line and the walk continues); (3) flushes
stdout, writes to stderr

```text
<message>
  at <file>:<line> in <function>        (innermost first)
  ... outer frames omitted              (only when truncated)
cleanup fault: <message>                (one per secondary fault)
```

and exits 67. Generated code must keep frame pointers (rbp / x29 chains) and must
not tail-call away frames; the runtime is built with `-C force-frame-pointers=yes`
(`.cargo/config.toml`). Frames outside `FuncTable` are skipped.

**Call depth.** Generated code finds the running isolate's header block with `msrt_isolate_hdr() -> *mut u8` (one block per isolate thread). Word 0, `limit: usize`, is the lowest stack address recursion may
reach (stack base plus a reserve of an eighth, 64 KiB to 1 MiB, and recursion may use at most the top 256 MiB of the stack; 0 = no
limit). Recursive-cycle functions do `if sp < hdr.limit { msrt_fault_depth() }`
on entry; there is no work on return. After the fault the limit drops into the reserve so
cleanups can run. **Cancellation.** The byte at offset 8, `cancel: u8`, becomes the signal
number after SIGINT/SIGTERM (unless shielded). Loops and calls poll it (relaxed load)
and call `msrt_cancelled() -> !`, which runs cleanups and exits 130 (SIGINT) or 143
(SIGTERM). A second stop request or 30 s later prints `incomplete cleanup: <reason>`
and exits 67.

**Cleanup stack (`with`).** `msrt_cleanup_push(f: fn(arg: *mut u8), arg: *mut u8) -> usize`
returns a handle; `msrt_cleanup_run(handle)` runs and removes that action (and any
newer pending ones first, innermost to outermost). On a fault the remaining actions
run LIFO shielded from cancellation.

**Guarded calls.** `msrt_guard_call(code: extern "C-unwind" fn(*mut u8), data: *mut u8,
msg_out: *mut StrVal) -> u8` runs `code(data)` as an isolated request and returns
0 when it returns normally. A fault inside it (user fault, call-depth limit, runtime
fault) runs the cleanups pushed since entry LIFO, shielded, restores the stack limit,
cancel shield and equality-cycle state, and returns 1 with the fault report (message
plus `at file:line in fn` frames, no trailing newline) as a new String in `*msg_out`
(owned by the caller; may be null to discard). A stop request that reaches
`msrt_cancelled` inside the guard runs the same cleanups and returns 2 with
`*msg_out = null`; the cancel flag stays set so the caller should stop soon after.
Guards nest: a fault leaves only the innermost one. Cleanups registered before entry
are untouched. Not unwound: values owned by the abandoned frames are only released
through cleanup actions, so a fault leaks anything not under `with`; the HTTP server's handler thunk registers its request
with the cleanup stack for this reason. Faults still exit
67 outside any guard. Implementation: `msrt_guard_enter` saves callee-saved registers
and the stack pointer and calls `code`; a fault jumps back to it (x86_64 and aarch64;
generated code needs no landing pads). Single threaded like the rest of the runtime.

**Tasks.** Cooperative stackful coroutines on the runtime thread (`task.rs`). There is no
parallelism and no preemption, so the allocator, reference counts and every other runtime
global stay non-atomic; a task runs until it parks or yields. This is a runtime facility for
natives (an HTTP server running handlers concurrently); the language has no concurrency
surface. Each task has its own stack (default 256 MiB of address space, committed lazily, 64 KiB
guard), cleanup stack, guard stack, stack limit, equality-cycle state and cancellation request;
the runtime swaps them on every switch, so faults, `with` cleanups and `msrt_guard_call`
behave per task.

```text
msrt_task_spawn(entry: extern "C-unwind" fn(*mut u8), arg, flags: u32, stack_bytes: usize) -> u64
msrt_task_yield()
msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32
msrt_task_sleep(ns: i64) -> u32
msrt_task_join(handle: u64, msg_out: *mut StrVal) -> u8
msrt_task_cancel(handle: u64)
msrt_task_current() -> u64
msrt_task_count() -> usize
```

`spawn` queues the task; it first runs when the caller parks or yields. `flags & 1` makes it
detached: nobody joins it and a fault in it ends the process (exit 67, like any unguarded
fault); wrap handler bodies in `msrt_guard_call` for per-request isolation. A joinable task runs
under a guard, and `join` returns 0 (returned), 1 (fault, report in `*msg_out`) or 2
(cancelled). Each joinable task is joined once, which also frees it. `stack_bytes` 0 means the
default.

`wait_fd` parks the task until `fd` is ready for `events` (`1` read, `2` write), the timeout
(negative: none) expires, or the task is cancelled. It returns the ready bits (`1`, `2`, plus `4`
for error/hangup), `8` for timeout or `16` for cancelled. A cancelled wait means the caller
should unwind with `msrt_cancelled()` (or return an error). Rules for natives:
- Use non-blocking descriptors and retry after `EAGAIN`; a blocking syscall stalls every task.
- One task may wait on a given descriptor at a time (a second waiter faults).
- Regular files cannot be polled and report ready at once.
- `sleep` is `wait_fd` with no descriptor.
- A native must be safe to re-enter whenever it waits: every park (`wait_fd`, `sleep`, `join`, a token wait) lets other tasks call the same native, on the same object or on shared thread state. Hold no `RefCell` borrow, no `&mut` into shared state and no thread-local guard across a park. Take shared scratch out of a `Cell` for the call (or allocate), keep invariants consistent before parking, and re-check state after waking. Two tasks on one object must get a typed error or the runtime's single-waiter fault, never a borrow panic.

Cancellation: `SIGINT`/`SIGTERM` wake every parked task with `16`, the main task first, so its
`msrt_cancelled()` runs its cleanups and exits 130/143. `msrt_task_cancel(h)` wakes one task
and sets its cancellation request (the cancel flag is per task). When every task is parked
with no descriptor or timer that can wake them, the runtime faults with "deadlock".

Worker isolates: `msrt_worker_spawn(entry, arg, done)` starts an OS thread with an arena,
scheduler and fault context of its own and runs `entry(arg)` as that isolate's main task. `arg` is
null or a block from `msrt_worker_arg_new(bytes, len)`; the entry moves it into its own arena with
`msrt_worker_arg_take` (the block is system-allocated, nothing else crosses). `done` is a remote
token of the caller: the worker posts it (outcome plus one) when it has ended. `msrt_worker_join`
then returns the outcome (0 returned, 1 fault with its report in `*msg_out`, 2 cancelled) and
frees the worker; `msrt_worker_cancel` raises the worker's cancel flag and wakes its poller. At
most 256 workers are alive at once (`msrt_worker_spawn` returns 0 beyond that). Generated code
finds the running task's header block (recursion limit, cancel flag) by masking the stack pointer
to the 256 MiB task-stack slot on Linux and macOS and through `msrt_isolate_hdr()` on Windows.

Cost (release, x86_64): a yield-switch is about 40 ns between two tasks and about 90 ns across
100; with 10,000 tasks it grows to about 650 ns because each task touches its own stack pages.
Spawn is an `mmap` plus guard `mprotect` unless a pooled stack (32 kept) is available.

## 8. Naming and catalogue

`msrt_<module>_<name>`; modules: `mem`, `rc`, `fault`, `cleanup`, `int`, `float`,
`bool`, `numbers`, `string`, `bytes`, `list`, `map`, `set`, `strbuilder`, `slot`,
`eq`, `hash`, `io`, `process`, `profile`. Future crates (`ms-std-fs`, `ms-std-json`...)
use their own prefix and link only when imported; they depend on `ms-rt-abi` and call
`msrt_*` for allocation and faults. The authoritative symbol list is the `#[no_mangle]`
items in `ms-rt/src` (`cargo doc -p ms-rt`); language names follow `stdlib/*.ms`
(`String.split` -> `msrt_string_split`). Argument order: receiver pointer(s), descriptors,
declared parameters, flattened optionals, `out` last.

Inline fast paths the code generator may open-code (part of the ABI):

1. Retain `if p != null { p.rc += 1 }` / release `rc -= 1; if rc == 0 { msrt_drop_slow(p) }`;
   a `String` release calls `msrt_string_drop(p)` instead, since a string holds no references.
2. List element address `ptr + i * desc.size` when `(i as u64) < len` (else the slow path:
   negative index, default, or `msrt_index_fault`).
3. List push: `if len < cap { store at ptr + len*size; len += 1 } else msrt_list_push*`.
4. Lengths: `StrVal.len @8`, `VecVal.len @8`, `MapVal.len @16`.
5. Stack-limit check and cancel-flag polling.
6. Checked `Int` arithmetic via overflow flags, calling `msrt_fault_int_overflow`.
7. `Optional` presence tests and payload loads.

## 9. Process entry, I/O, profiler

`msrt_start(main_fn: extern "C" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8) -> i32`
is called from the C `main` the compiler emits. It installs tables and signal
handlers, starts the profiler when requested, runs `main_fn` on a dedicated thread
with a 1 GiB stack, validates the exit
code (`0..=125`, else the Go fault message), flushes stdout and returns the status.
`msrt_args(out: *mut VecVal)` fills a `List[String]` (argv[1..]).

`msrt_io_write_stdout(s)`, `msrt_io_write_stderr(s)`, `msrt_io_flush()`: stdout is
buffered (64 KiB) and flushed before any stderr write, on fault, exit and by
`msrt_io_flush`. `msrt_process_exit(code: i64) -> !` flushes and exits (no cleanup).

### Symbol table (`Tables`)

```text
Tables { abi_version: u32, reserved: u32, funcs, func_count, lines, line_count, strings, strings_len }
FuncEntry { addr: usize, size: u32, name_off: u32, file_off: u32, line: u32 }    24 bytes, sorted by addr
LineEntry { pc: usize, line: u32, file_off: u32 }                                16 bytes, sorted by pc
```

`abi_version >= 3` appends `line_scopes: *const u32` (one per `LineEntry`), `scopes: *const ScopeEntry`
and `scope_count` (header 80 bytes) so frames of inlined functions appear in fault traces:

```text
ScopeEntry { name_off: u32, file_off: u32, parent: u32, call_line: u32 }          16 bytes
```

`line_scopes[i]` is 0 for the function itself, else a 1-based `scopes` index. A frame prints its
line in the innermost scope's function, then for each enclosing scope the `call_line` in the parent
(parent 0 = the physical function). Older tables (version < 3) are read without these fields.

Offsets index NUL-terminated strings in `strings`. `addr`/`pc` are link-time
(relocated) addresses; `pc` is the start of a code range (extends to the next entry; a frame's line is the last entry with `pc <= return_addr - 1` inside the function); `file_off == u32::MAX` means the
function's file. Names are those shown in fault traces (`inner`, `Point.norm`,
`main.lambda2`); only source functions belong in `FuncTable`.

### Profiler

`MS_PROFILE=<path>` enables sampling. `MS_PROFILE_HZ` (default 1000, 1..=10000);
`MS_PERF_MAP=1` also writes `/tmp/perf-<pid>.map`. `ITIMER_PROF` raises SIGPROF;
the handler is async-signal-safe: it reads pc and frame pointer from `ucontext`,
walks the frame-pointer chain inside the stack bounds recorded at start (at most
128 frames) into a preallocated ring of 65,536 samples (no allocation; overflow is
counted). At exit (normal, fault or stop) the runtime resolves pcs through
`FuncTable` and writes **folded stacks**, outermost first:

```text
main;work;inner 412
main;work 17
# dropped 0
```

Unresolved frames are `0x<hex>`; runtime frames collapse to `[runtime]`.
`ms profile <program> [args]` sets `MS_PROFILE` to a temp file, runs the native
program, converts the folded file to pprof output, and with `--perf-map` sets
`MS_PERF_MAP=1` so `perf record --call-graph fp` can symbolize.
