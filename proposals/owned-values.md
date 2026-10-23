# Owned-value model for String, List, Map, Set and Queue

Status: **proposed**; decision 1 below is made, revised after a skeptic review (verdict: direction defensible, plan not ready to build until the implicit-copy cost is measured and the staging is split). Date: 2026-10-22.
Direction (from the project owner): represent strings "the Rust way", consistently, everywhere in the stdlib including maps, lists, sets and queues.

## 1. Goals and non-goals

Goals
1. Every container and text value follows one rule: an owned, header-less value with a single owner, a deep `copy` through its descriptor, and a drop that frees its buffer. No reference counts on ordinary data (DESIGN.md decision 1).
2. A string never needs a pointer chase to learn its length or reach its bytes.
3. Slicing operations (`trim`, `split`, `slice`, `basename`) can avoid allocation without a new source-level type.
4. Hash maps, sets, lists, queues and deques containing strings use the same slot, descriptor and native-call conventions as every other element type.

Non-goals: changing scalar-indexed `length()`/indexing semantics; changing `Shared[T]`, closures or handle objects (they stay refcounted, by design); string algorithms.

## 2. What is inconsistent today (verified in source)

| Value | Representation | Ownership |
|---|---|---|
| `List[T]`, `Bytes`, `StringBuilder` | `VecVal {ptr,len,cap}`, 3 words, header-less | owned, deep copy (`ABI.md` §4, `ms-rt-abi`) |
| `Map[K,V]`, `Set[T]` | `MapVal`, 6 words, header-less | owned, deep copy |
| `String` | 1 pointer to `StrObj {rc, drop, len, scalars, data, NUL}` | refcounted, shared (`ABI.md` §3) |
| `Optional[String]` | nullable pointer, `KIND_SHARED` | refcounted |
| `Queue[T]` | pointer to `QueueObj {Obj hdr, ...}` (`ms-rt/src/queue.rs`: "copies of a queue value share one queue") | refcounted, shared |
| `Deque[T]` | Manuscript record over `List[Optional[T]]` (`stdlib/deque.ms`) | owned, independent copy |

So strings and `Queue` are the two ordinary-data types that still use reference counting, and `Queue` copies alias while `Deque` copies do not. The lowering never emits retain (`grep retain crates/ms-lower/src` is empty): sharing of a string happens only inside `desc.copy` (`.clone()`) and inside runtime natives that return their input unchanged (`trimmed`, `retained` in `ms-rt/src/string.rs`, `ms-std-core`, `ms-std-net`).

## 3. Design

### 3.1 Layout

- `String` is `StrVal {ptr, len, cap}`, byte-identical to `VecVal` (24 bytes, three `I64` leaves), with no flag bits: `len` is the UTF-8 byte length, `cap` the allocation capacity, and every list/bytes drop, copy and grow path stays valid unmasked. Static literals have `cap == 0` and are never freed. Whether a string is ASCII is not cached in the value: `length()` and scalar indexing use a vectorized ASCII check (memcpy-speed), and compile-time-known cases (literals, concatenation of known-ASCII parts) lower to the byte length directly. A cached flag can be added later if measurements demand it.
- No NUL terminator is stored. Natives that need a C string (a few in `ms-std-fs`, `ms-std-process`, `ms-std-system`, `ms-std-net`) build one in a scratch buffer, exactly as Rust's `CString` does.
- `StringBuilder` is a `VecVal` of bytes already; `freeze` becomes a move (it copies today).
- `Optional[String]` uses the same layout rule as `Optional[List[T]]` (presence flag plus payload leaves). `ptr == null && cap != 0` is not used as a niche, so every `Optional[X]` for non-pointer `X` is uniform. `Optional[String]` becomes 32 bytes.
- `Queue[T]` becomes an owned value `QueueVal {buf, head, len, cap}` (a ring or head-indexed buffer), copied deeply, dropped by `msrt_queue_drop`, with a descriptor kind `KIND_QUEUE`; `Deque[T]` keeps its implementation or moves onto the same value later. `Set[T]` already shares `MapVal` with `Map`.
- Descriptors: `msrt_desc_string` becomes `builtin(24, 8, KIND_STRING)`; `KIND_STRING` drop frees `ptr` when `cap` has an owned capacity, copy allocates and copies bytes, equality and hash read `(ptr, len)` directly. `KIND_SHARED` keeps covering `Shared[T]`, closures, handle objects and `Optional` of those (nullable-pointer path in `layout.rs:231-235` unchanged for them); `Optional[String]` leaves it and follows the `Optional[List]` rule.

### 3.2 Calling convention

Aggregates already cross the native ABI by pointer to the value (`*const VecVal`), with a trailing out pointer for constructed results. Strings adopt the same: parameters are `*const StrVal`, results are written to an out `StrVal`. This is the one mechanical ABI change and it is uniform with lists. Natives written in Rust use a shared `&str`-like accessor from `ms-rt-abi` (`StrVal::as_bytes`), so most native code changes only its signature prologue.

### 3.3 Costs this design accepts

- `Shared[String]` is a `Shared` box holding a three-leaf payload; box layout follows from leaves.
- Value width 8 to 24 bytes: records with strings, `List[String]` and `Map[String, V]` slots grow. Rust's `String` is also 24 bytes.
- Every `Op::Copy` of a string allocates and copies instead of retaining. This is the principal risk and it is larger than `.clone()`: the lowering emits `Op::Copy` on `Str` routinely (`ms-lower/src/func.rs:372` `owned()`, `closure.rs:586`, `iface.rs:378,536`, `fsinfo.rs`, `fswalk.rs`, `eq.rs:111`), and Cranelift lowers each to a retain (`ms-clif/src/lower.rs:333-336`). `ms-mir/src/opt/copyelim.rs:120-206` removes copy/drop pairs for strings under `str_source_stable`; its soundness argument assumes a string copy is idempotent and free and must be re-proved for an allocating copy. Record or list construction from a borrow, interface boxing, closure capture, call-through-closure results and match-payload re-owning are all candidate sites. Mitigation: lend at read accessors and make copyelim exhaustive, and gate the switch on a numeric budget of static and dynamic `Op::Copy`/`Drop` of `Str` per benchmark (§6).
- `length()` on a non-ASCII string is an O(n) scalar count (today it is cached in the header after the first call). Indexing by scalar on non-ASCII was already O(n).

### 3.4 Views (the `&str` equivalent) without new syntax

`trim`, `split`, `slice`, `basename` return a `StrVal` with `VIEW` set, pointing into the receiver, with no allocation. Source type stays `String`.
- Safety comes from existing machinery, extended: today lending is inferred from a `return` of a part of a parameter (`OWNERSHIP.md`, "Borrowed results"), and a native has no body, so a native lending marker in the stdlib declaration (`bindings.json` or a declaration attribute) is new work. With it, `let t = s.trim()` blocks changes to `s` until `t`'s last use.
- When a view reaches a consuming position (stored in a list or record, returned, passed to a consuming parameter, captured by an escaping closure), the checker rejects it with a mechanical `.clone()` fix, exactly where Rust requires `.to_string()` (§9 decision 1: no implicit copies). `names.append(line.trim().clone())` allocates once, at the append, visibly. A view is immutable and has no `&mut str` counterpart; in-place edits need an owned `String`.
- MIR tracks provenance with a distinct internal type so the check is static: `Str` is always owned or static; `StrView` flows only through borrow positions, and `StrView -> Str` is the explicit `to_owned` op. There is no runtime `VIEW` bit. This is a type-system change, not a flag: every position that accepts `Str` (generics, `Shared[String]`, `Map` keys, match payloads, `Optional`, records, closure and interface boxing, return paths) needs a coercion or a rejection rule, and the ownership fixtures `getter_result_stored` and neighbours change meaning for view-producing natives. It is therefore a separate, later stage that must be prototyped on one stdlib function first.

## 4. Interactions, by component

| Component | Change |
|---|---|
| `ms-rt-abi` | `StrVal`, flag constants, `QueueVal`, `KIND_QUEUE`; remove `StrObj`, `STR_*_OFFSET` |
| `ms-rt/src/string.rs` | all ops on `(ptr,len)`; shared statics for empty/ASCII bytes become `cap == 0` values; `trimmed` returning the input becomes returning a view or the moved value |
| `ms-rt/src/desc.rs`, `map.rs`, `vec.rs` | `KIND_STRING` slot code; `StrKey` hash/eq fast path reads `(ptr,len)`; list sort/search comparators for strings |
| `ms-rt/src/queue.rs` | rewrite as an owned value |
| `ms-clif/src/layout.rs`, `lower.rs` | `Str` becomes three leaves; remove hard-coded header offsets (`lower.rs` StrLen 24, `string_eq_literal` 16/32); `StrLen`, `StrEq`, literal compare, #974 byte/ASCII ops read `len`/`ptr` leaves directly |
| `ms-lower` | string literals as constant triples; `Ty::STR` uses become multi-leaf; interpolation and concat build owned values; the new `StrView` type and `to_owned` insertion |
| `ms-check` | lending marker for stdlib string methods; `OWNERSHIP.md` rule for view-to-owned |
| `ms-mir` | `Str` multi-leaf in verifier/interpreter; `StrView`; optimizer rules that assume one-pointer strings (`copyelim`) |
| `stdlib/*.ms`, `bindings.json` | no source change for owned operations; add lending annotations for view-returning operations; `Queue` becomes an owned type |
| `ms-std-*` crates and `ms-rt` (about 20 crates; `StrObj` appears in over 30 files; strings cross the native ABI as `i64` today) | signatures take `*const StrVal` and return via out pointer; `Optional[String]` results use flag plus out; C-string conversions explicit; `ms-std-core`, `json`, `regex`, `csv`, `fs`, `io`, `net`, `process`, `random`, `system`, `terminal`, `url`, `rt`; `stdlib/toml.ms` and `yaml.ms` need an audit of how they reach strings |
| MIR interpreter | `Val::Str(Rc<str>)` diverges from the native model and cannot catch ownership bugs; decide whether it models the three-leaf value or stays an oracle |

## 5. Alternatives considered

- Keep `StrObj`, add a cached `{len|ascii}` word to records (O3): fixes one access pattern only, not lists, maps or queues, and does not make the model consistent.
- Fat `{hdr, len|ascii}` with refcounted bytes (O2): still reference counting, still special-cased `Optional[String]`, native result adapters; rejected by the consistency goal.
- Owned flat string without views: simplest, but leaves `trim`/`split`/`basename` allocating; views (3.4) are additive and can land after the representation change.
- Small-string inline storage (24-byte value can hold 23 bytes inline): compatible with 3.1 as a later optimization (`cap` flag); not part of this design.

## 6. Staging and verification

The review of this note found that the switch can be split by separating the value shape from ownership. Stages:
1. Measurement and prerequisites (mergeable): count static and dynamic `Op::Copy`/`Drop` of `Str` per benchmark (a `stats`-style counter in `ms-rt` and a MIR pass report) and set a numeric budget; replace hard-coded header offsets in `ms-clif` (`lower.rs` StrLen 24, `string_eq_literal` 16/32, `cg.rs:29,506-515`) with constants; make `copyelim` exhaustive for strings.
2. `Queue` as an owned value (mergeable alone; fixes the copy-aliasing inconsistency with `Deque`).
3. Shape first: `String` becomes the three-leaf value `{ptr,len,cap}` in layout, descriptors, call ABI, natives and lowering, with `ptr` still pointing at a refcounted block (copy is a retain, drop a release). This lands the layout, the `*const StrVal` ABI, `Optional[String]`, descriptor and map/list slot changes, and the stdlib crate ports, and already removes the length pointer chase. Gate: `make conform`, leak sweep, benchmark tables.
4. Ownership second: replace the refcounted block with a uniquely owned buffer (copy allocates, drop frees, `freeze` moves), gated by the stage 1 copy budget and any lending changes needed to meet it.
5. Views: prototype lending on one stdlib function, then the `StrView` MIR type and explicit `.clone()` at owning positions, then the rest of `trim`/`split`/`slice`/`basename`.

Gates for stage 3: no regression above noise on `competence`/`kernels`/`programs`; `records_1M_x20` scan at or below Rust; zero new leaks in `leak-check`; Miri model tests (`ms-rt/src/model_tests.rs`) cover the new string value.

## 7. Risks and open questions

1. Implicit string copies (3.3) may dominate programs that read strings out of collections. Stage 1 measures this before the switch; if high, getters must lend first.
2. Provenance tracking for `StrView` in MIR must not be bypassed by any native that stores its argument; every native that retains an input must take it as consumed.
3. Language-visible loosening of the borrowed-result rule needs an `OWNERSHIP.md` decision record and ownership fixtures (accept and reject) for views.
4. LLVM consumes the Cranelift IR, so there is one lowering plus string-literal data emission (`cg.rs:500-516`); there is no separate per-platform offset risk, but literals must be emitted as constant triples.
5. `length()` complexity for non-ASCII strings changes; if a workload needs it, cache the scalar count in a side field of builders or in the `ASCII`-style flags, not in a header.
6. Coordination: the Strings thread has PRs in flight touching the same lowering (`StrByte`/`StrAscii`, `string_eq_literal`); stage 1 must be sequenced after them.

## 8. Static copy budget (stage 1 data)

`sh bench/perf/copy-report.sh target/release/ms <ms.toml>` counts `copy` instructions in the lowered MIR by type. On the benchmark programs: competence 11 copies (6 `str`, 1 `Item` record holding a string), kernels 8 (no strings), programs 7 (3 `opt<str>`, 1 `str`). Static counts are small, but the loop-resident ones decide the cost: the `strmap_10M` loop executes two `str` copies per iteration (`let w = words.get(...)` copies the list element, then `m.add(w, ...)` copies it again to give the map an owned key), i.e. 20M retains today and 20M allocate-and-copy operations under unique ownership. The first is removable by binding the `let` as a lexical borrow (the ownership pass already classifies it so; lowering still copies); the second is semantically required (the map stores an owned key, as `entry(w.clone())` does in Rust). Dynamic counts are not yet measured.

## 9. Decisions

1. **Implicit copies are errors (2026-10-22, owner direction).** Lowering never inserts a copy of a non-Copy value from a borrow. Where a consuming position receives a borrowed value, including native collection calls such as `m.add(w, ...)` and `list.append(borrowed)`, the checker rejects the program with a mechanical `.clone()` fix, so the cost of every copy is visible in source. The change lands together with a sweep of the stdlib, examples, conformance fixtures and documentation. Moves at a value's last use and lexical borrows (`let w = xs.get(i)`) need no copy.
2. **Unique ownership and views are the target (2026-10-23, owner direction).** Strings follow borrow and ownership like `List` and `Bytes`: stage 4 removes the reference count (copy allocates, drop frees, moves at last use) and stage 5 adds immutable borrowed views (`&str` in Rust terms; a view cannot be mutated and blocks changes to its source while live). Documentation describes strings as owned values and marks the buffer count as transitional until stage 4 lands.
3. **Rust behavior is the model for views (2026-10-23, owner direction).** Immutable, borrowed, never silently promoted to owned; duplicating takes an explicit `.clone()`. Differences from Rust stay syntactic only: no lifetimes in source, lexical borrows.
