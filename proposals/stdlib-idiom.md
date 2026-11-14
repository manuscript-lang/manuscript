# Idiomatic stdlib: os, net, fs, Table

## Summary

- `os/fs.ms`, `os/process.ms` and `net/net.ms` hold 3 to 4 modules each, stringly/boolean-typed arguments, and boilerplate the language should absorb.
- Split them along their existing seams, replace flag/mode/kind stand-ins with enums and option types, and move `Table` into `cli`.
- Decision requested: approve the split map and the renames below before any code moves (all are breaking renames).

## Status

Proposal, 2026-11-05, checked against `80fd348b`. Decided by Chinmay: unused numeric conversion spellings may be dropped (Addendum 4). Not yet reviewed by a skeptical subagent (AGENTS.md requires that before building). `.ms` below is signature sketch, not run through `ms check` (no `ms` binary in this session). Ships in the same PR as its first stage, not alone.

## Problem

Measured on this checkout (line counts, `grep`):

- `os/fs.ms` 1030 lines: file I/O, `PathParts`/`PathOperations`/`posix`/`win32`/`basename`/`join` (pure path text, no I/O), watch, temp dirs, `FileSystem` fake-seam. Path functions are exported from `fs` next to `net`-style names that collide (`format`, `parse`, `resolve`, `join`).
- `os/process.ms` 746 lines: spawn/run/signals, environment and cwd, hostname/user/home, `cpus`, `network_interfaces`, `metrics`, `memory_usage`, priority, umask, uid/gid. `os/metrics.ms` is an unrelated histogram.
- `net/net.ms` 1070 lines: IP/CIDR, DNS, URL, TLS certs, TCP, UDP, WebSocket, HTTP client factory, `serve`, `Network` capability. `request`/`request_bytes` here, `fetch.ms` `fetch`/`Fetcher`, and `HttpClient` are three client APIs.
- Stringly or `Bool`/`Int` stand-ins: `open(path, flags: String, mode: Int)`, `access(path, mode: Int)`, `seek(offset, origin: Int)`, `stat(path, follow_links: Bool)` (no default; every call writes `true`/`false`), `os_type() String`, `endianness() String`, `constants() Map[String, Int]`, `set_identity(kind: String, id: Int)`, `chmod(mode: Int)` with octal ints.
- `FileInfo` has 30 fields: `directory`, `symlink`, `regular`, `fifo`, `socket`, `block_device`, `char_device` are seven Bools for one kind, plus `exact: Map[String, BigInt]` mirroring numeric fields.
- Mixed completion models in one module: `read_file`/`write_file` return `Promise[T]`; `list`, `stat`, `remove`, `append_file` block and return `T!`. Callers cannot guess which.
- Text/bytes doubling: `write_file`/`write_file_bytes`, `append_file`/`append_file_bytes`, `write_atomic`/`write_atomic_bytes`, handle `write`/`write_bytes`, `write_at`/`write_at_bytes`, `read_file` vs `read_lines`.
- Boilerplate: 9 `*Args` record types (`ReadArgs`, `WriteArgs`, `ConnectArgs`, `ConnectTlsArgs`, `ConnectTlsConfigArgs`, ...) exist only to move values into `owned_promise`; `connect`, `connect_tls`, `connect_tls_config`, `connect_unix` are four spellings of one verb; `Raw*`/wrapper pairs (`RawConnection`/`Connection`, `RawDatagramSocket`, `RawWebSocket`, `RawWatcher`) repeat per resource.
- Seams duplicated: `FileSystem`, `Commands`, `Network` interfaces each re-declare the module's free functions (`fs.ms:147-247`, `process.ms:128`, `net.ms:416`) so fakes can be passed.
- `io/table.ms` (135 lines) is a terminal layout helper that imports nothing from `io`. `cli.ms` hand-rolls aligned columns three times with `pad_end` (`cli.ms:668-721`) and never uses it. Only `tests/e2e/testdata/stdlib/table.ms` imports it. `format` takes `max_rows`/`max_cells`/`max_bytes` and spends ~35 lines on overflow arithmetic; `spaces` is `" ".repeat(count, none).get("")`.

## Design

### 1. Split by seam (no behavior change)

| Today | After |
| --- | --- |
| `os/fs.ms` path half | `os/path.ms`: `basename`, `dirname`, `extension`, `join`, `normalize`, `relative`, `resolve`, `parse`, `format`, `separator`, `delimiter`, `PathParts`, `PathOperations`, `posix`, `win32`, `matches_glob` |
| `os/fs.ms` remainder | `os/fs.ms`: file, directory, watch, temp, copy/move/glob |
| `os/process.ms` env half | `os/env.ms`: `environment`, `set_environment`, `load_environment`, `working_directory`, `change_directory`, `arguments`, `home_directory`, `which` |
| `os/process.ms` host info | `os/system.ms`: `SystemInfo`, `cpus`, `network_interfaces`, `memory_usage`, `available_memory`, `uptime`, `hostname`, `user_info`, `os_type` |
| `os/process.ms` remainder | `os/process.ms`: `run`, `spawn`, `Subprocess`, signals, priority, identity, `ProcessInfo` |
| `os/metrics.ms` | `data/histogram.ms` (it is a histogram, not OS metrics) |
| `net/net.ms` | `net/ip.ms` (IP, CIDR, DNS), `net/url.ms` (`Url`, query, components), `net/tls.ms` (certs), `net/websocket.ms`, `net/net.ms` (TCP/UDP/Unix, `Network`, `serve`) |

Splitting removes the `format`/`parse`/`resolve` collisions (`url.parse`, `path.parse`); each import list names its module. Precedent: `crypto/crypto.ms`.

### 2. Types instead of stand-ins

```manuscript
// sketch
export enum FileKind:
    File
    Directory
    Symlink
    Fifo
    Socket
    BlockDevice
    CharDevice

export enum OpenMode:
    Read
    Write       // create or truncate
    Append
    ReadWrite

export enum Seek:
    Start
    Current
    End

export enum Os:
    Linux
    Macos
    Windows
```

- `FileInfo.kind: FileKind`; keep `directory`/`symlink` as methods (`info.is_directory()`), delete the four device Bools and `regular`.
- `exact: Map[String, BigInt]` becomes explicit `BigInt` fields only where `Int` can overflow (`size`, `inode`, timestamps); the map is a lookup-by-string-name anti-pattern. Open question 2.
- `stat(path, follow_links: Bool = true)`; `open(path, mode: OpenMode = OpenMode.Read)`; `access(path, mode)` takes `List[Access]`; permissions stay `Int` (octal) because that is the OS value.
- `os_type() String` becomes `os() Os`; `endianness()`, `constants()` and `set_identity(kind: String, ...)` become `set_user(id)`/`set_group(id)`. Compile-time `Os` removes string compares such as `os_type() == "Windows_NT"` (`process.ms:541`).
- Failure kinds stay as today (`Error.kind` strings); out of scope here.

### 3. One completion model

- File and network operations that wait on the OS return `Promise[T!]`-style via the one existing path; short metadata calls (`stat`, `list`, `remove`, path text) block. State the rule in the module comment and apply it uniformly: today only `read_file`/`write_file`/`connect*` are promises.
- Needs a language/stdlib primitive so `*Args` records vanish: `owned_promise` should accept a closure that moves its captures (see `architecture/closure-capture-rules.md`). Verify the rule permits `fn: read(path, max)` capturing owned `path`; if it does not, keep `*Args` and treat as a language gap, filed as an issue per project rules.

### 4. Text and bytes as one API

- `write_file(path, data: Bytes)` and `String.to_bytes()` at the call site, or an interface `Writable` that `String` and `Bytes` both `impl`. Recommendation: the interface, so `write_file(p, "text")` and `write_file(p, bytes)` both type-check and `*_bytes` names go away (6 functions, 5 methods).
- `connect`: one `connect(address, tls: TlsOptions?, timeout)` plus `connect_unix`; `connect_tls`/`connect_tls_config` collapse into `tls:`.

### 5. Seams

- Keep one interface per capability (`FileSystem`, `Commands`, `Network`) but generate nothing by hand: module free functions become the default instance, `host()` pattern already exists at `fs.ms:586`. Delete the duplicate doc comments by documenting the interface only and having free functions say "same as `FileSystem.x`".
- Drop `Raw*` types from the public surface (`export` removed); only the wrapper type is exported. `WebSocket`/`Connection` are what callers hold.

### 6. Table into `cli`

- Move to `stdlib/cli/table.ms`; imported as `import Table, Align from "@std/cli/table.ms"`. `cli.ms` and `cli/` coexist like `crypto`.
- Reshape as a type with methods (language-design taste: methods over free functions): `Table(columns: [Align.Left, Align.Right])`, `var table.add(row)`, `table.render()`; `cli.ms` help uses it, replacing the three `pad_end` loops (net removal of ~40 lines in `cli.ms`).
- Drop `max_rows`/`max_cells`/`max_bytes`: callers bound their own row source; this deletes `budget`/`add`/the pre-pass (about 60 of 135 lines). A table is output the caller already holds in memory.
- Expose the width primitive as `String.display_width() Int!` (in `string.ms`/`unicode.ms`) instead of a `msstd_table_cell_width` hidden under `internal/table.ms`; `ms-std-table` stays the only native (`unicode-width`, already a dependency, no new crate). Control rejection stays: `EBADMSG`.
- Keep `Alignment` renamed `Align` (shorter, used in constructors).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/os/*.ms`, `stdlib/net/*.ms`, `stdlib/cli*.ms`, `stdlib/data/histogram.ms` | split, retype, rename | `tests/e2e/testdata/stdlib/*` ported, `make conform` |
| `stdlib/internal/{fs,net,process,table}.ms` | `extern fn` signatures unchanged except `open`/`seek`/`os` natives | `cargo xtask symbols` |
| `crates/ms-std-table`, `ms-std-fs`, `ms-std-net` | `display_width` export, `Seek`/`OpenMode` decode | crate tests |
| `crates/ms-check/build.rs` | embed new file list | `make verify` |
| `documentation/`, `wiki/`, LSP snapshots | imports, generated reference | `make docs-check` |
| `stdlib/concurrency/promise.ms` | closure-move into `owned_promise` (stage 3 only) | conformance case |

## Alternatives

- Do nothing: every new OS feature keeps growing 1000-line modules; `format`/`parse` collisions persist. Cost is concrete (collision constraint in the runtime checklist).
- Smallest version: only move Table and split `fs` path half. Cheap (stages 1 and 6) and recommended as the first PR; skips type changes.
- Runner-up: keep module layout, only add enums. Fails the collision and size problem; rejected.
- Table in `io/` renamed only: keeps an import path nobody reads; `cli` is the only in-tree consumer candidate.

## Stages

1. Move Table to `cli/table.ms` as `Table` type, use it in `cli.ms`, drop limits, add `String.display_width`. Check: `cli` and table e2e green.
2. Split `path`, `env`, `system`, `histogram`, `ip/url/tls/websocket` with no signature change. Check: `make conform`, `make docs-check`.
3. Enums (`FileKind`, `OpenMode`, `Seek`, `Os`), defaults, `Writable`, `connect(tls:)`. Check: `make verify-full`, Windows matrix dispatched (platform-sensitive).
4. Completion-model uniformity and `*Args` removal once the closure-move check passes.

Each stage is one PR; stages 2 and 3 may merge if the diff stays reviewable (fewer, larger PRs).

## Open questions

1. Breaking renames: acceptable now (pre-1.0)? Recommendation: yes, in the same stage as each split, no aliases.
2. `FileInfo.exact`: replace with a few `BigInt` fields, or drop and document `Int` saturation? Recommendation: keep `BigInt` only for `size` and `inode`.
3. `Writable` interface vs separate `_bytes` functions? Recommendation: interface.
4. Should `Promise` vs blocking be decided per module by one documented rule (OS-wait vs metadata)? Recommendation: yes.

## Addendum: redundant code and awkward patterns (grep, `80fd348b`)

Counted over `stdlib/**/*.ms`; each item is a candidate for stage 2 or a separate cleanup PR.

- **Re-implemented helpers.** `min`/`max` exist as `math.min[T: Comparable]`, yet `cli.ms:729` (`max_int`), `data/utf8.ms:96` (`min_int`) and `test/bench.ms:26-31` redefine them. `hex4` is copied in `data/toml.ms:1021` and `data/yaml.ms:1920`, and so is `quote_text` (`toml.ms:1026`, `yaml.ms:1925`). `is_space` is defined in `data/json.ms:276` (bytes) and `data/xml.ms:284` (strings), while `unicode.ms` has `is_digit`/`is_ascii` that `text/template.ms:306` also redefines. `hex_digit` is in `encoding.ms:223` and `toml.ms:354` with different meanings.
- **Manual padding.** `hex4` pads with `while digits.length() < 4: digits = "0".concat(digits)` (quadratic, two copies); `yaml.ms:1464` `pad(width)` builds spaces in a loop; `table.ms:135` uses `" ".repeat(count, none).get("")`. One `pad_start`/`repeat` call each. `cli.ms` already calls `pad_end`.
- **Error construction.** The same literal is built inline many times: `"encoding: invalid data"` 16 times, `"filesystem: invalid input"` 11, `"logging: resource is closed"` 10, `"jwt: invalid key"` 9. Only `cli.ms` uses a named constructor per error (`cli_unknown_flag`, ...) and 28 such helpers exist overall. Recommend one rule: a module-private constructor fn per error, as `cli.ms` does.
- **Wrapper-only functions.** `os/fs.ms` has 41 functions whose body is `return msstd_fs_*(...)`, `os/process.ms` 34, `net/net.ms` 12. Each repeats its signature three times (extern in `internal/`, `FileSystem`/`Network` interface method, exported free fn) plus a doc comment. If the extern is declared with the public signature and exported directly, the free-function layer disappears where no adaptation (a `Promise`, a default) happens. Needs a check that `export extern fn` is allowed outside `internal/`; the runtime checklist says natives are wrapped by ordinary functions, so confirm before relying on it.
- **`owned_promise` argument records.** 13 call sites across stdlib (`fs` 4, `net` 7, `fetch` 3, `process` 2); 9 one-use `*Args` types (stage 4).
- **Optional `Bool` flags.** 38 `Bool = false` parameters; at least `create_directory(recursive)`, `remove(recursive)` and `write_file(replace)` read as bare `true` at call sites (`remove(p, true)` in `fs.ms:861`). Use labels at call sites in stdlib itself, or enums (`Replace`/`Keep`). Recommendation: labels, no new type.
- **Nested `match` candidates** (flat-match rule, AGENTS.md): `data/toml.ms:1097,1154`, `data/yaml.ms:449,775`, `io/io.ms:735`, `net/net.ms:288`, `text/template.ms:734`. Crude indent scan, not verified; `make repo-check` is the authority.
- **Size outliers.** `data/yaml.ms` is 2076 lines against `toml.ms` 1201 and `json.ms` 461; the three parsers share quoting, escaping and number scanning that could sit in one `data/text_scan.ms`. Largest `.clone()` counts: `text/template.ms` 55, `data/yaml.ms` 50, `cli.ms` 40, `toml.ms` 35 — each worth a pass against the borrow-by-default rule, since many are likely avoidable borrows. Hypothesis until measured.

Proposed stage 2b: delete the duplicated helpers above (min/max, hex4, quote_text, is_space), standardize error constructors, add labels to bare Bool call sites. No API change; check is `make verify` plus a before/after line count.

## Addendum 2: streams and pipes to cut code (grep, `80fd348b`)

`io/streams.ms` has only `lines`, `from_list`, `from_bytes`, `map`, `collect`, `read_all`, `copy`. `for x in stream.wait()` already drains a stream (`streams.ms:141`), yet hand loops remain. Steps take input first, so `a | b | c` composes them.

- **Hand-written drain loops, 6 copies of the same 10 lines.** `checksum.ms:68` (`crc32_of`), `checksum.ms:87` (`adler32_of`), `hash.ms:154` (`crc64_of`), `crypto.ms:142` (`digest`) each run `while true: read().wait() ... update(data) ... close()`. `net/http.ms:217` and `http.ms:426-470` (`read_body`, `read_rest`, `read_more`, `over_limit`, about 45 lines) re-implement `read_all` with a limit. Fix: add `feed(input, var sink: Updatable) Unit!` (or `fold`) to `streams.ms`, where a small interface `Updatable { var fn update(Bytes) }` is structurally satisfied by `Crc32`, `Adler32`, `Crc64` and `algorithm.hasher()` (each has `update`; needs explicit `impl`); each `*_of` becomes `input | feed(var sum)` then `sum.value()` (about 4 lines each). `read_body` becomes `read_all` over a stream view of `exchange.read()` (about 3 lines, if `HttpExchange` gains a `reader()`). Net: about 90 lines removed.
- **Buffered twin of every streamed API.** `compress`/`compressed`, `decompress`/`decompressed`, `pack`/`tar_entries`, `base64_encode`/`base64_encoded`, `hex_encode`/`hex_encoded`, `parse`/`json_reader`, csv/sse/multipart. The buffered forms call separate natives with their own `max_bytes` handling. Rule to adopt: keep the buffered convenience only when it is `from_bytes(data) | step | read_all(max)`, written in `.ms`; drop the second native. Candidates: `compress`, `decompress` (`archive.ms:73-80`), `hex`/`base64` pairs. Cost check before deleting: bench `compress` 1 MiB buffered vs piped; keep a native when the stream path is more than about 10% slower (project perf rule).
- **Missing combinators that would replace loops.** `filter`, `take(n)`, `chunks(n)`, `batch`, `merge`, `tee`, `fold`. `map` shows the pattern: one `Transform` plus a 2-line wrapper. Add only those with an in-tree user; found users: `filter` (`fs.glob` exclude, `router` access log), `take` (`collect(max_items)` becomes `take(n) | collect`), `fold` (the checksum loops above).
- **Directory and watch as streams.** `Directory.read()` (one entry per call, `fs.ms:446`) plus `list` (whole list) plus `glob` all exist; `Directory` could `impl Source[DirectoryEntry]` so `open_directory(p) | filter(...) | collect`, mirroring `watch` which already returns a `ReadStream`. `tree.walk` (`tree.ms:347`, manual `pending` stack) can then be a stream too, bounding memory on large trees.
- **`FileHandle.read_lines(max_bytes, max_lines)` native** duplicates `reader() | lines(max_bytes) | take(max_lines) | collect` once `take` exists; delete `msstd_fs_file_read_lines`.
- **Process output.** `process.run` collects stdout/stderr natively with `max_output_bytes`; with `Subprocess.stdout()` as a `ReadStream`, `run` is `spawn` + two `read_all` + `wait` in `.ms`. Candidate to delete a native; keep if timeout/kill-group semantics cannot be expressed (hypothesis).
- **Pipes between tasks.** `pipe[T](capacity)` exists; no stdlib code uses it to join stages (`from_list|from_bytes` are only used by `test/iotest.ms`). Examples in docs, not stdlib changes.

Stage 0 (before stage 1): add `feed`, `filter`, `take`, `fold` to `streams.ms` with tests, rewrite the 6 drain loops and `read_body`. Check: `make verify`; expect roughly 120 fewer lines and one fewer native per buffered twin removed. Open question: remove buffered natives outright, or keep as thin `.ms` wrappers? Recommendation: wrappers, same names, so no break.

## Addendum 3: shrinking `stdlib/internal` (grep, `80fd348b`)

`stdlib/internal/*.ms` is 1761 lines declaring 545 `extern fn`: `math` 92, `process` 90, `fs` 73, `net` 63, `promises` 48, `crypto` 29, `time` 28, `io` 27, `http` 24. Each native costs an `extern` line, a Rust symbol (`rt_symbols.txt`, `cargo xtask symbols`), an ABI test and usually a wrapper in `.ms` (see wrapper counts above).

- **Dead declarations (delete now).** Not referenced by any `stdlib/**/*.ms` except their own file: `msrt_promise_ready`, `msrt_cells_full`, `msrt_cells_take_result` (`internal/promises.ms`), `msstd_time_sleep` (`internal/time.ms:27`). `msstd_system_working_directory` (`internal/process.ms:130`) is imported at `process.ms:60` but only `msstd_process_working_directory` is called (`process.ms:599`). The Rust symbols still exist (`crates/ms-rt/src/{promise,task,cells}.rs`, `ms-std-time`), so the PR removes both sides and regenerates `rt_symbols.txt`. Check: `cargo xtask symbols`, `cargo nextest run -p ms-native`.
- **Pure-text natives that should be `.ms`.** 15 `msstd_path_*` (basename, dirname, join, normalize, relative, parse, format, glob match, ...) in `crates/ms-std-path` (1264 lines Rust); URL parse/format/query in `crates/ms-std-url` (1247 lines). Both are string manipulation with no OS access, so they belong in Manuscript (project rule: Rust only for small runtime primitives). Win: Rust lines deleted, natives 15 + 6 fewer, and path functions become ordinary borrowing code. Risk: `matches_glob` and `resolve` need the same behavior on Windows; port the existing Rust tests as `.ms` tests first, run the full CI matrix. Perf must stay within the bench baseline (hypothesis: path ops are not hot).
- **Getter fan-out.** `process_info_*` are 10 natives (`pid`, `parent_pid`, `executable`, `arguments`, `os`, `architecture`, `uid`, `gid`, `effective_uid`, `effective_gid`) read through 17 call sites in `process.ms`; `system_metrics_*` and `system_cpu/network/user` add about 31 more. One native returning the struct (`ProcessInfo`, `SystemMetrics`, `UserInfo` already exist as `.ms` types) replaces each family: expected about 40 fewer externs. This is also how `FileInfo` and `stat` already work.
- **Share and close counting.** 9 natives (`*_share`, `*_close_if_last`, `listener_raw_owner`, `release_unadopted`) back `Connection`, `DatagramSocket`, `Listener`, `WebSocket` and their `Raw*` twins (`net.ms`). That is reference counting on handles, which the one-owner model removes. Hypothesis, needs a read of `net.ms` ownership code: with owned handles plus `Closeable`, the share/close_if_last natives, the `Raw*` exports and the duplicated wrapper types go away. This is the largest single item and belongs with stage 3 of the net split, not as a drive-by.
- **Handle operation families.** 17 `msstd_fs_file_*` natives plus 41 wrapper fns in `fs.ms`: one native per `FileHandle` method. Keep the natives that touch the OS (`read_at`, `write_at`, `seek`, `sync`, `lock`); `read_lines` and `read_vectors`/`write_vectors` can be `.ms` over those (see Addendum 2).
- **Audit, not claims.** `ms-std-html` is 6768 Rust lines (`parse.rs` 2382) behind 12 externs and a 131-line `data/html.ms` (since then parsing moved to Manuscript and the crate keeps only escape and unescape); `math` has 92 externs I have not classified (likely float intrinsics, which stay). Neither is judged; list them as follow-up audits with a measured cost/benefit before touching, per the proposal rule.
- **Guard.** Add a `repo-check` rule failing on an `extern fn` in `stdlib/internal` that no `.ms` file imports, so the surface cannot regrow unnoticed (pattern: `stream-names-allowed.txt`).

Stage 0b (with stage 0): delete the 5 dead declarations and their symbols, add the repo-check rule. Stage 2c: port `path` then `url` to `.ms`. Stage 3 adds the getter-struct collapse and the share/close removal. Open question: port `url` to `.ms`, given parsing security (RFC edge cases, fuzz corpus)? Recommendation: yes, but only after carrying the Rust tests and fuzz inputs over unchanged.

## Addendum 4: the `<Type>Operations` interfaces (read `stdlib/intrinsics.ms`, `ms-check/src/stdlib.rs:1004`)

`intrinsics.ms` is 427 lines and 13 interfaces. Eight numeric ones (`Int8`, `Int16`, `Int32`, `UInt8`, `UInt16`, `UInt32`, `UInt64`, `Float32`) plus `Int`/`Float` hold about 112 method declarations. A diff of `Int8Operations` against `Int32Operations` shows they differ only in the type name and in which conversions are lossless (`to_int16() Int16`) versus checked (`to_int8() Int8?`). The checker finds them by name: `{receiver}Operations` for each primitive (`stdlib.rs:1006`).

- **Shared by every integer type, repeated in each interface:** `to_string_radix`, `to_float`, `to_decimal`, `compare(other: T)`, `sign`, `to_float32`, `to_float64`, and `abs` (signed only). About 8 declarations with identical doc text, 8 times, so roughly 64 lines say 8 things.
- **Language limit:** interfaces have no inheritance and no default impls (`contracts.md:40`), so the shared part cannot be inherited. A generic interface can carry it, since `CloneOperations[T]` already does: `interface IntegerOperations[T]` with `compare(other: T) Int`, `abs() T`, `to_string_radix`, `sign`, and float and decimal conversions.
- **Design:** the checker maps each primitive to a list of interfaces, `Int32` to `[IntegerOperations[Int32], Int32Conversions]`, instead of one `Int32Operations`. `Float`/`Float32` share `FloatOperations[T]` (`is_nan`, `is_finite`, `compare`, `abs`, `sign`, `truncate_to_int`). Lookup in `stdlib.rs:1004` loops over a list; method resolution already unions inherent methods, so the change is local. Hypothesis until traced through `ms-check` method lookup and the LSP `reference_order.rs` test.
- **Conversions are the remaining repetition** (about 48 declarations: each type lists a lossless or a checked form for every other type). Options:
  1. Keep declared, trimmed to what code uses; measure uses with `grep` of `to_int8`/`to_uint16`/... across `stdlib` and `tests` first.
  2. Generate the matrix in `ms-check` from a width/signedness table. Smallest text, but violates "derive from declarations, not Rust tables" (AGENTS.md).
  3. Replace the matrix with generic `to[T]()` once the language has an integer-conversion bound. Not available today.
  Recommendation: 1 now, and do not add 2. Expected result: `intrinsics.ms` from 427 to about 200 lines.
- **Same pattern elsewhere to check:** `StringTextOperations` (`string.ms:116`) next to `StringOperations` (two interfaces for one receiver), and `PathOperations` (`fs.ms:959`) with `posix()`/`win32()` duplicating the module's own path functions. Both fold into the path module work above; not otherwise judged.

Stage 0c: share the numeric core through generic `IntegerOperations[T]` and `FloatOperations[T]`, trim conversions to those used. Check: `cargo nextest run -p ms-check -p ms-lsp`, `make conform`, `ms search_symbol Int32` output unchanged for retained methods (LSP snapshots). Open question: acceptable to drop unused conversions (a break for rarely used spellings)? Recommendation: yes, after grep shows no in-tree use, with one release note.

## Addendum 5: one convention for arguments, options and limits (grep, `80fd348b`)

Today a caller cannot predict where a setting goes. Measured across `stdlib/**/*.ms` outside `internal/`:

- **Optional params without a default.** 128 of 137 `max_*: Int?` parameters have no `= none`, so callers write the trailing `none` (77 call sites end in `none)`; e.g. `path.split("/", none)` in `tree.ms:56`, `list(path, none)`, `.repeat(count, none)`). Only 9 declare `= none`.
- **Three container styles for the same job.** Bound settings live in loose params (`read_file(path, max_bytes)`, `table.format(max_rows, max_cells, max_bytes)`), in `*Limits` records (`JsonLimits`, `YamlLimits`, `TomlLimits`, `HtmlLimits`, `ArchiveLimits`, `SseLimits`) and in `*Options` records (`FetchOptions`, `CopyOptions`, `GlobOptions`, `WatchOptions`, `CsvOptions`, `PromiseOptions`). `json.parse` takes `limits: JsonLimits?` (optional record, then `.get(JsonLimits())` inside), `json_reader` takes `limits: JsonLimits? = none`, `fetch` takes `options: FetchOptions = FetchOptions()`.
- **Same knob, different names.** `max_bytes`, `max_entry_bytes`, `max_total_bytes`, `max_response_bytes`; `GlobOptions` has both `max_entries` and `max_results`; `timeout` is required positionally in `connect*` and `Subprocess.wait`, defaulted in `FetchOptions` (`seconds(30)`) and optional in `run`.
- **Strings and overlapping flags in records.** `CopyOptions.clone: String = "none"`, `WatchOptions.overflow: String?`, `pack`/`compress(format: String)` ("case-sensitive; others ENOTSUP"); `CopyOptions` has `replace` and `error_on_exists = true`, which state one fact twice.

### Rule (one place to look)

1. **Required inputs are positional; every optional input has a default and is never required.** `none` is the default for `X?`; callers never pass a trailing `none`. A parameter that cannot be defaulted is required, and is not `X?`.
2. **A function takes at most three parameters in total** (required plus optional; the receiver does not count). Optional ones are labeled and defaulted: `json.parse(text, max_bytes: 1 << 20)`; no record to construct, import or learn.
3. **A fourth parameter moves the optional ones into one record named `<Thing>Options`**, every field defaulted, passed last as `options: <Thing>Options = <Thing>Options()`; required inputs stay positional. Settings shared by several functions use the same record even under three. `Limits` is not a second kind: limits records are renamed `Options` where they stay (`ArchiveOptions`, shared by `unpack`/`tar_entries`) and dissolve into params where the function stays within three (`json`, `yaml`, `toml`, `html`, `sse`). Never `Options?`.
4. **Standard names**: `max_bytes`, `max_entries`, `max_depth`, `timeout`; per-item bounds are `max_item_bytes` style only when two bounds coexist. Delete `max_results`, `max_response_bytes` (becomes `max_bytes`), `max_entry_bytes` vs `max_total_bytes` becomes `max_entry_bytes` and `max_bytes`.
5. **Enums, not strings, for modes** (`CloneMode`, `OverflowPolicy`, the existing compression-format enum for `compress`/`pack`); remove `error_on_exists` (`replace: false` already means an existing file errors).
6. **Timeouts** are `timeout: Duration? = none` everywhere an operation can wait, last in the list.

### Effect and check

- About 128 declarations gain `= none`; about 77 call sites drop an argument; 5 `*Limits` types and their `.get(...Limits())` unwrapping go; `Options?` parameters (`yaml.parse`, `toml.parse`, `html.parse`, `json.parse`) become labeled params, so `parse(text)` and `parse(text, max_depth: 64)` both read directly.
- Add a `repo-check` rule: an exported function parameter of type `T?` with no default fails, and a parameter named `*options*` or `*limits*` must have a default. (Pattern: `stream-names-allowed.txt` for existing offenders, shrinking to empty.)
- Mechanical, so it lands as one stage right after the numeric work: `make conform`, `make docs-check`, LSP snapshots regenerated. Because it changes call shapes it is a breaking change in the same sense as the renames above; positional trailing `none` stays valid because defaults accept explicit values.
- Decided by Chinmay: the threshold is three parameters in total, not three optional ones. Functions over it today (e.g. `copy`, `glob`, `run`, `spawn` with 7, `table.format`) get or keep an options record; `read_file(path, max_bytes)` and `list(path, max_entries)` stay loose.

### Addendum 4 follow-up: what blocks it (traced 2026-11-05)

- `world.intrinsic` is `HashMap<Name, Ty>`, one interface per primitive, read by four consumers: `contracts.rs:1586` (method lookup), `hints.rs:608`, `editor.rs:71` (completion), `ms-tooling/src/guide/api.rs:467`. A list of interfaces touches all four.
- The native identity of a primitive method is `"{receiver.id}/{name}"` (`contracts.rs:1590`, `is_receiver_native`), so `Int32Operations/compare` becomes `IntegerOperations/compare`; lowering and `rt_symbols`/ABI tables that key on the old string must be traced before the move. Generic `compare(other: T)` also needs `T` bound to the receiver by `substitution(t)`.
- The conversion matrix cannot be trimmed by grep: every `to_*` name is used somewhere (`to_int8` 10, `to_uint16` 4, `to_float64` 2 sites), and a name does not say which receiver. Trimming needs a compiler-assisted run (delete candidate, run `make conform`/e2e) per pair.
- Result: this is a compiler change (`ms-check`, `ms-lower`, `ms-tooling`) with its own PR, not a stdlib tidy-up. Not started; ask for a go-ahead as a separate workstream.

### Addendum 4 outcome

Implemented: `IntegerOperations[T]` (all integer types) and `SignedIntegerOperations[T]` (`Int`, `Int8`, `Int16`, `Int32`) hold the shared operations; `stdlib.rs` `SHARED_OPERATIONS` lists the members and each primitive gets its own interface plus the shared ones applied to itself. `intrinsics.ms` went from 427 to 333 lines. The conversion matrix (`to_int8` and the other sized conversions) stays declared per type: every name is used somewhere and grep cannot tell which receiver, so trimming needs a per-pair compiler-assisted run. `Float`/`Float32` could share `FloatingPointOperations[T]` the same way (about 6 declarations); not done.
