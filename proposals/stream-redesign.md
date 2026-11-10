# Streams: one shape for values over time

Status: **approved by Chinmay 2026-11-03, building** (2026-11-03, checked against `d28b56d5`). Builds on `concurrency-redesign.md` (approved; implementation starting on `claude/project-thread-nchfqv`) and covers what its decision 4 deferred: the stream implementations written in Manuscript. Snippets are unchecked. Lands after the concurrency PR, as one PR.

## In one paragraph

A stream is anything that produces or accepts values over time and can wait. There is one reading type, `ReadStream[T]`, and one writing type, `WriteStream[T]`. Files, sockets, stdio, processes, pipes, WebSockets, datagrams, tickers, signals, file watchers, terminal events, HTTP bodies, SSE, JSON and lines are all one of these with a concrete `T`. There are two things to implement: a `Source[T]` makes a new stream, and a `Transform[A, B]` changes one. Pipelines are the existing `|` operator. Native code only moves bytes in and out; everything else is Manuscript. Things that never wait (hashers, CRCs) are not streams.

## Why: what doesn't make sense today

1. **About 15 shapes for "the next value".** `ReadStream.read(max_bytes)`, `Iterator` plus an `error()` side channel (`LineReader`, `Scanner`), `next() T!` (`SignalStream`, `FileWatcher` returning `List[FileEvent]`), `Directory.read`, free `next_event(var reader)` (SSE), `RawTerminal.next_event`, `WebSocket.receive`, `DatagramSocket.receive`, a blocking `Iterator` (`Ticker`), push decoders (`SseDecoder.feed`, `JsonDecoder.feed`), `Channel`/`Transport`, log `Transport`, `File`/`Files`, `ResponseBody`, `HttpExchange.read`. None compose with each other.
2. **Real streams don't implement the interface.** `Connection`, `ResponseBody`, `HttpExchange`, `WebSocket` and `FileHandle` each have their own `read`/`write`/`write_bytes`, with a `timeout` argument per call; `FileHandle` also has `reader()`/`writer()` adapters on top.
3. **Two writes everywhere.** `write(String)` and `write_bytes(Bytes)` on `WriteStream`, `Connection`, `HttpExchange`, `FileHandle`, log `Transport`.
4. **Line reading lives in four places.** Rust `Stream::read_buffered_line` with a stdin stash (`ms-std-fs/src/stream.rs:402-490`), the compiler's MIR loop for `read_all`/`copy`/`read_line` over any stream (`ms-lower/src/streamloop.rs`, 371 lines) with its accumulator (`ms-std-io/src/accumulate.rs`, 214), and in Manuscript `LineReader`, `BufferedReader` and `Scanner` (`buffered.ms`, 453 lines), each with its own buffer.
5. **Natives call back into Manuscript streams.** `compress_stream`, `decompress_stream` and HTTP request bodies take a `ReadStream` that Rust calls through the `ReadSource` closure ABI (`ffi/native.rs:998`). Under the new model a Manuscript `read` can wait, and native code cannot.
6. **Ownership is prose.** "Closing the result closes `input`", "the caller owns `sink`", "keep it in a `var` binding". The one-owner model already says this when an adapter takes its input by move.
7. **Chunk size is on every call.** `read(max_bytes)` mixes a buffering choice into the stream contract.
8. **`BufferedWriter`** duplicates the write buffer every native `WriteStream` now has (concurrency decision 6).

## Rules added by review

- **Supersedes** the concurrency proposal where it makes `ReadStream` an interface or adds `read_chunk`/`write_text`; those become `text_writer` and `Source`.
- **Cancellation keeps items.** Each fused stage's `out` list lives in the stream, so a cancelled read that already consumed input keeps the produced items for the next `read`; "takes no value" holds only when nothing was consumed. Fixtures cover multi-stage, `finish`, and `through_writer` flush on close, not only `lines`.
- **Windows** pipes and consoles cannot be polled: their reads run on the blocking pool, and cancel abandons the read and discards or stashes the bytes in the stream's own read-ahead, never in a global.
- **Scope-end drop of a `WriteStream`** hands buffered data to the runtime like any close; code that needs delivery errors calls `flush().wait()`.
- **Placement:** a `Source` runs in the waiting task; a native-headed pipeline moved into a promise is placed by the pinning rule in Internal model 7.
- **Measure first:** a prototype of `stdin() | lines` and a five-stage fusion is benchmarked before the Rust deletions; `lines` must not allocate more than one `String` per line, and the `wc -l` gate is pass/fail.

## Public API (the whole of it)

`@std/io/io.ms`

```manuscript
export opaque type ReadStream[T]                 # one owner; dropping it closes it
impl ReadStream[T]:
    var fn read() Promise[T?]                    # one step; none at the end
    var fn wait() Waiting[T]                     # for x in s.wait(): each item is T!, so errors arrive in the loop

export opaque type WriteStream[T]
impl WriteStream[T]:
    var fn write(value: T) Unit!                 # moves value into the buffer; never waits; Closed once the reader is gone
    var fn flush() Promise[Unit]                 # waits until drained: the backpressure point
    fn buffered() Int                            # items or bytes not yet drained

# A new stream: next may wait.
export interface Source[T]:
    var fn next() T?!
export fn stream[T](source: Source[T]) ReadStream[T]

# A changed stream: never waits; appends zero or more items per input, and what it held back at the end.
export interface Transform[A, B]:
    var fn feed(value: A, var out: List[B]) Unit!
    var fn finish(var out: List[B]) Unit!
export fn through[A, B](input: ReadStream[A], transform: Transform[A, B]) ReadStream[B]
export fn through_writer[A, B](output: WriteStream[B], transform: Transform[A, B]) WriteStream[A]

export fn stdin() ReadStream[Bytes]
export fn stdout() WriteStream[String]           # see open question 2
export fn stderr() WriteStream[String]
export fn stdout_bytes() WriteStream[Bytes]      # same buffer as stdout()
export fn pipe[T](capacity: Int) Pipe[T]         # unchanged from the concurrency proposal
```

`@std/io/streams.ms` (Manuscript; every function takes its input first and by move, so each one is a `|` step)

```manuscript
export fn from_list[T](items: List[T]) ReadStream[T]
export fn from_bytes(data: Bytes, chunk_bytes: Int = 65536) ReadStream[Bytes]
export fn map[T, U](input: ReadStream[T], f: fn(T) U) ReadStream[U]
export fn filter[T](input: ReadStream[T], keep: fn(T) Bool) ReadStream[T]
export fn text(input: ReadStream[Bytes]) ReadStream[String]                     # UTF-8, cut only at scalar boundaries
export fn text_writer(output: WriteStream[Bytes]) WriteStream[String]
export fn lines(input: ReadStream[Bytes], max_bytes: Int? = none) ReadStream[String]
export fn split(input: ReadStream[Bytes], delimiter: UInt8, max_bytes: Int? = none) ReadStream[Bytes]
export fn collect[T](input: ReadStream[T], max_items: Int?) List[T]!
export fn read_all(input: ReadStream[Bytes], max_bytes: Int?) Bytes!
export fn copy[T](input: ReadStream[T], output: WriteStream[T]) Int!           # flushes past 64 KiB or 1024 items, and at the end
```

Format modules add their own steps, each a `Transform` inside: `json_reader[T]`/`json_writer[T]` (concurrency proposal), `sse_events`, `compress(format, level)`, `decompress(format, max_bytes)`. Their transforms are private; to decode bytes already in hand, use `from_bytes(data) | sse_events | collect(none)`.

## Transforms and pipelines

- **A pipeline is the existing `|` operator.** `x | f(a)` is already `f(x, a)` (`expressions.md` "Pipe flows"), so no new syntax or type.
- **A reusable pipeline is a function.** Name the flow and it becomes a step in other flows.
- **A transform is a state machine that never waits.** One interface covers 1-to-1 (`map`), 1-to-many (`lines` over a chunk), many-to-1 (JSON over chunks) and filtering, on the read side (`through`) and the write side (`through_writer`).
- **Stages fuse.** `through` over a stream that is itself a `through` appends to that stream's flat list of stages instead of wrapping it. A five-stage pipeline is one source calling `feed` five times per item, with one reused `out` list per stage and no promise between stages. Only the head `read` waits.
- **Pipelines run in the reader's task.** Stages are pulled lazily; to run a stage elsewhere, start a `promise` that `copy`s into a `pipe` and read the pipe.
- **Pipelines end in a consumer:** `copy`, `collect`, `read_all`, or a `for … in s.wait()` loop.

## Example

```manuscript
# A reusable pipeline: Bytes in, entries out.
fn log_entries(input: ReadStream[Bytes]) ReadStream[LogEntry!]:
    return input
        | decompress(Gzip, max_bytes: none)
        | lines
        | filter(fn line: line.contains("ERROR"))
        | map(parse_entry)

fn tail_errors(path: String, out: WriteStream[String]) Int!:
    file := try open(path).wait()
    entries := file.reader() | log_entries
    var count = 0
    for entry in entries.wait():
        e := try entry
        try out.write("{e.time} {e.message}\n")
        count += 1
    try out.flush().wait()
    return ok(count)

# A transform of your own: running totals.
type Running:
    total: Int
impl Transform[Int, Int] for Running:
    var fn feed(value: Int, var out: List[Int]) Unit!:
        self.total += value
        out.append(self.total)
        return ok(unit)
    var fn finish(var out: List[Int]) Unit!:
        return ok(unit)

sums := from_list([1, 2, 3]) | through(Running(0)) | collect(max_items: none)   # [1, 3, 6]

fn proxy(var client: Connection, var upstream: Connection) Unit!:
    {input: from_client, output: to_client} := client
    {input: from_upstream, output: to_upstream} := upstream
    _counts := try wait_all([
        promise(fn: copy(from_client, to_upstream)),
        promise(fn: copy(from_upstream, to_client))
    ])
    return ok(unit)
```

## Closing

- **Both stream types are `Closeable`, and nothing else is.** Scope end closes them, as for any `Closeable`. `close` never waits and is idempotent.
- **`Source` and `Transform` don't close.** A stream owns its source or stages and drops them when it closes; whatever they own (an inner stream, a file) is closed by that drop. A source holding some other resource implements `Closeable` itself. So closing a pipeline closes everything upstream with no prose rules.
- **A read can't race a close.** A pending `read()` promise holds a `var` borrow of the stream, so the checker rejects `close` while it lives; dropping the promise cancels the read first.
- **Closing a writer doesn't drop data.** Buffered bytes go to the runtime, which drains them in the background and before exit (concurrency decision 6). A drain error after close is lost, so call `flush().wait()` first when delivery matters. `close` returns `ok(unit)` for every stream.
- **Ends close separately.** Closing a `Connection.output` is `shutdown_write`, and dropping the record closes both. Closing a pipe's reader makes writers fail with `Closed`. Closing every writer ends the reader after it has read what was sent.

## How the rest of the stdlib uses streams

Four rules, written into the runtime checklist and checked by `ms-repo-check` from declarations, not name lists:

1. **Anything that yields values over time and can wait returns a `ReadStream[T]`**, and anything that accepts them is a `WriteStream[T]` (the table below). No exported type has its own `next`, `receive`, `read`, `feed` or `write_bytes`; repo-check rejects an exported method with one of those names outside `io.ms`.
2. **Functions that take a stream take it first and by move**, so each one is a `|` step and ownership is in the signature. Consumers end a flow (`digest`, `copy`, `Logger`, `render_to`); adapters return a new stream.
3. **A format offers values and one stream step.** It keeps `parse(Bytes)`/`stringify(value)` for whole values and adds a stream step only where input can be large or unbounded, built on a private `Transform`: `json_reader`/`json_writer` (NDJSON), `csv_rows`/`csv_writer`, `sse_events`, `compress`/`decompress`, `base64_encode`/`base64_decode`, `hex_encode`, and `crc32`/`crc64`/`digest` as consumers. TOML, YAML, XML, semver, JWT and PEM stay value-only.
4. **`Iterator` is for sequences that never wait** (`List`, `Map`, string scalars, ranges), and `ReadStream` is for everything that can. `from_list` and `collect` bridge them. A `for` over a stream without `.wait()` is a checker error pointing at `.wait()` (concurrency proposal).

| Module | Gains |
| --- | --- |
| `data/csv.ms` | `csv_rows(input: ReadStream[Bytes], options) ReadStream[List[String]!]`, `csv_writer(output: WriteStream[Bytes]) WriteStream[List[String]]` |
| `data/json.ms` (absorbs `jsonstream.ms`) | `json_reader[T]`, `json_writer[T]` |
| `data/encoding.ms` | `base64_encode`, `base64_decode`, `hex_encode`, `hex_decode` as steps |
| `data/checksum.ms`, `crypto.ms` | `crc32(input)`, `crc64(input)`, `digest(input, algorithm)` consumers |
| `io/archive.ms` | `compress`, `decompress`; `tar_entries(input) ReadStream[ArchiveEntry]` for archives too big for memory |
| `text/template.ms` | `render_to(template, values, output: WriteStream[String])` |
| `log.ms` | `create(output: WriteStream[String], …)` |
| `net/mime.ms` | `multipart_parts(body) ReadStream[Part]` for uploads |

## How each stream maps

| Today | Becomes |
| --- | --- |
| `Connection.read/write/write_bytes(…, timeout)`, `shutdown_write` | `Connection` record with `input: ReadStream[Bytes]`, `output: WriteStream[Bytes]`, `info`; timeouts via `.wait(timeout:)`; dropping `output` is `shutdown_write` |
| `FileHandle.read/write/write_bytes/append_file*/read_lines` | `reader()`/`writer()` only; positional `read_at`/`write_at` stay and return promises |
| `File`, `Files` (io.ms) | deleted; `fs.open` |
| `HttpExchange.read`, `send_headers`, `write`, `write_bytes` | `body: ReadStream[Bytes]`; `var fn respond(status, headers) WriteStream[Bytes]` (no writes before headers); `send` stays |
| `ResponseBody`, `request_stream`, `Fetcher.stream`, request body `ReadStream` | `ClientResponse.body: ReadStream[Bytes]`; uploads write to a `WriteStream[Bytes]` the request returns |
| `WebSocket.receive/send/send_bytes/ping` | `input: ReadStream[WebSocketMessage]`, `output: WriteStream[WebSocketMessage]`; ping is a message kind |
| `DatagramSocket.receive/send/send_bytes` | `input: ReadStream[Datagram]`, `output: WriteStream[Datagram]`; the datagram carries its address |
| `Subprocess.stdin()/stdout()/stderr()` | fields, movable into promises |
| `Ticker` (blocking `Iterator`) | `ticker(period) ReadStream[Instant]` |
| `SignalStream`, `FileWatcher`, `RawTerminal.next_event`, `Directory.read` | `ReadStream[Int]`, `ReadStream[FileEvent]` (one event per item), `events() ReadStream[TerminalEvent]`, `entries(path) ReadStream[DirectoryEntry]` |
| `SseReader`, `next_event`, `body_stream`, `SseDecoder`, `JsonDecoder` | `sse_events`, `json_reader` |
| `compress_stream`, `decompress_stream` (Rust calls back into the stream) | `compress`/`decompress`: a private transform over a Rust push primitive `feed(Bytes) Bytes!`/`finish() Bytes!` |
| `LineReader`, `Scanner`, `ScanMode`, `ScanStep`, `read_line`, `read_lines`, `BufferedReader` | `lines`, `split`, `map`; anything else is a `Transform` |
| `BufferedWriter`, `tee`, `multi_writer`, `map_writer`, `take`, `concat`, `read_chunk` | deleted (no stdlib users; only e2e fixtures such as `tests/e2e/testdata/stdlib/streams.ms`; `read_chunk` is only in the concurrency text) |
| `section(file, offset, length)` | `file.reader_at(offset, length)` |
| `channel_reader`/`channel_writer`, `Channel`, `Transport` | `pipe[T]` (already in the concurrency PR) |
| log `Transport`, `stream_transport`, rotating transport | `Logger` writes to a `WriteStream[String]`; rotation stays inside the logger (concurrency PR: `fstat` on its own handle) |
| `digest(stream, algorithm)` | stays in `crypto.ms`, over `ReadStream[Bytes]` |
| `Hasher`, `Crc64`, `MapHash` | unchanged: they never wait, so they are not streams |

## Internal model

1. **`ReadStream[T]` and `WriteStream[T]` are one word.** The upper bits tag native, source or pipeline; the rest is an index into the runtime's flat stream table (fd or socket, state, read-ahead offsets, as a structure of arrays) or a pointer to the boxed source. Native streams dispatch on the tag without a vtable, which also removes the MIR-built stdio vtables (`native.rs:618`, `std_stream`).
2. **Native reads are I/O promises** (concurrency internal model, the `{state, token, result}` array): try the system call, register with the poller only when it would block.
3. **A `Source` runs when its promise is waited, in the waiting task.** `read()` returns a deferred entry in the same promise array holding a `var` borrow of the stream, so rule 2 holds and no task or stack is made per item. `wait_first`/`wait_all` and `wait(timeout:)` give it its own task only when it must run beside others. Cancellation lands at a wait inside `next`; state in the source's fields survives, and a cancelled inner read takes no value (concurrency rule 5).
4. **Writes never wait, so the write side needs no `Source` counterpart.** Native writers, pipe writers and `through_writer` are the only `WriteStream`s; `through_writer` calls `feed` and hands the output to its inner writer.
5. **Natives never call Manuscript streams.** Bytes go into natives through `write` and come out through `read`. This deletes the `ReadSource` closure ABI, `streamloop.rs`, `accumulate.rs`, the `msstd_io_copy`/`read_all`/`read_line` natives and their lowering, and the Rust line buffer with its stdin stash.
6. **One buffer per transform, no caches.** `lines` holds only the unterminated tail of the last chunk, as `Bytes` plus a start index; it compacts when the free head passes half the buffer, so work stays linear.
7. **A native stream's promises run on its thread.** TLS, WebSocket and HTTP/2 keep one session per connection in Rust, shared by its `input` and `output` (a TLS read can need a write, a WebSocket read answers pings). So a promise that captures a native stream, or a pipeline headed by one, is placed on the thread whose poller holds that stream instead of the least loaded one; this extends the concurrency proposal's placement rule and keeps its list of objects synchronized across threads at three. Values leave that thread only through a pipe, which is already synchronized. A plain TCP, Unix or UDP stream follows the same rule for one behaviour everywhere.

## Rust deleted

Every Rust special case for streams goes; what remains is listed under "Rust that stays". Line counts are today's (`d28b56d5`).

| Where | What | Why it can go |
| --- | --- | --- |
| `ms-lower/src/streamloop.rs` (371) | MIR loops for `read_all`, `copy`, `read_line` over any stream | `read_all`, `copy` and `lines` are Manuscript |
| `ms-std-io/src/accumulate.rs` (214) | accumulator behind those loops | same |
| `ms-lower/src/codecstream.rs` (398) | MIR-generated `read` for `compress_stream`/`decompress_stream` | `compress`/`decompress` are Manuscript transforms over the codec's `feed`/`finish` |
| `ms-std-archive/src/compress/stream.rs` (420) | pull wrapper that drives the codec from a `ReadStream` | the codec keeps only push `feed`/`finish`; about 150 lines stay |
| `ms-rt/src/ffi/native.rs:995-1040`, `ffi/mod.rs:18` | `ReadSource`: Rust calling a compiled `ReadStream` closure | natives never call Manuscript streams |
| `ms-std-net/src/ffi/http_client.rs:197-215,379` | `Upload`, a request body pulled from a `ReadStream` | the request returns a `WriteStream[Bytes]` that Manuscript writes into |
| `ms-lower/src/natiface.rs:247-258, 640-665, 706-709, 1036-1100` | interface vtables over runtime handles for `ReadStream`, `WriteStream`, `File`, `SignalStream`; the "streams are `@std/io` handles" rename; the `IfaceIs` native-or-Manuscript fast path for `read_line` | opaque stream types dispatch on their tag; `natiface.rs` keeps only non-stream handles (`Network`, `FileSystem`, `Clock`, ...) |
| `ms-lower/src/native.rs:347-359, 618-623, 3514-3576`; `closure.rs:1281-1300` | `io/stdout`, `io/stderr`, `io/read_line`, `io/read_all`, `io/copy` lowering and the MIR-built stdio vtable (`build_stream_method`) | stdio are ordinary native streams; the rest is Manuscript |
| `ms-lower/src/stdnative.rs:61-67` | `msstd_io_copy`, `read_all`, `read_line`, `stdin` handle rows | same |
| `ms-std-fs/src/stream.rs:3-4, 76-170, 235, 389-490` and `ms-rt/src/glue/mod.rs:417-440` (`STDIN_PENDING`) | line reader, `pending` read-ahead, the stdin stash shared between handles, `poll(2)` slicing and `poll_cancel` | `lines` owns the buffer; cancellation is the I/O promise's (Windows: below) |
| `ms-std-fs/src/stream.rs:113-138` (`Stream::standard`) | stdin handle rebuilt per `stdin()` call, sharing the stash | one native stdin stream in the stream table |
| `ms-check/src/effects.rs:115-121` | effects by interface name (`@std/ReadStream`, `@std/File`, `@std/WriteStream`) | effects come from the stream methods' declarations (project rule: no Rust name lists) |
| `ms-std-net` connection, WebSocket and datagram natives | `write`/`write_bytes` pairs, per-call `timeout` arguments, `ping`, `shutdown_write` entry points | one `write(Bytes)`; timeouts are `wait(timeout:)`; ping is a message; half-close is closing `output` |
| `ms-std-process` signals, `ms-std-fs` watcher, `ms-std-terminal` events, `time` ticker | each one's own `next`/`close` natives and lowering rows | each is a native stream in the table, read through the one `read` path |

About 2,000 lines of Rust are deleted (1,900 counted in the rows above, plus the per-type natives in the last two rows, which will be counted when the work starts). About 500 lines of Manuscript are added: `streams.ms`, `lines`, the transforms and the codec wrappers.

## Rust that stays

The native stream table: open, read, write, flush and close for each fd, socket, pipe and console (Windows console input included), as I/O promises. TLS, HTTP/1.1, HTTP/2 and WebSocket framing. Compression and hashing push primitives. Nothing else.

## Checks

- Line throughput: `wc -l` and a grep over a 1 GB file through `stdin() | lines`, against today's Rust `read_line` path and Go `bufio.Scanner`; within 5% of today or it does not merge. New `bench/perf/stream-lines` page.
- A five-stage fused pipeline against the same work in one hand-written loop; `copy` of 1 GB file to socket and pipe to pipe, against today.
- `bench/perf/web` against its latest dated result.
- `make verify-full`, `make leak-check`, and the full Linux/macOS/Windows matrix (console stdin, pipes, sockets).
- Fixtures: a cancelled `wait(timeout:)` on `lines` loses no line; chunk boundaries inside a line, a CRLF and a UTF-8 scalar (`from_bytes(…, 1)`).

## Size

The public surface goes from about 45 stream names across 15 shapes to 24. Deleted: `buffered.ms` (453 lines), `channels.ms`, most of `streams.ms`, `streamloop.rs` (371), `accumulate.rs` (214), the `ReadSource` ABI, the Rust line reader and stdin stash, `SseReader` and both public decoders, `File`/`Files`, log `Transport`. Call sites re-counted at the start; by grep over `.ms`, `.md` and `.rs` at review time: `.receive(` 187, `read_line(` 94, `read_all(` 86, `.write_bytes(` 49, `next_event(` 34 (`lines(` is noisy); the first count of the thread was lower, so recount with a pinned scope before the codemod. Codemod as in the concurrency PR.

## Alternatives considered

- **Keep `ReadStream[T]` an interface** (the concurrency proposal's text). Implementers would write both `read() Promise[T?]` and `wait()`, and Manuscript code cannot make a promise without a task per item. `Source.next` is one method and costs nothing per item. Putting `next` on the stream itself would let callers pause with no `wait` in sight.
- **A `Sink[T]` to implement for writers.** Writes never wait, and the only Manuscript writer in the stdlib is a transform on the write side, which `through_writer` covers.
- **A byte `Reader` with `peek`/`read_exact`/`read_until`.** One user today (`BufferedReader`); a `Transform` covers framing. Add it back when a protocol needs it.
- **Public decoder transforms next to the stream steps.** Two names per format; `from_bytes(...) | step` covers bytes already in hand.
- **A `Pipeline[A, B]` type.** A function already composes with `|`; fusing at `through` gives the same speed.
- **Transforms as `Source`s** (each wraps its input and waits per item). No fusing, no write side.
- **Keep the Rust line reader for speed.** It is the fourth copy of the same buffer logic and cannot serve Manuscript streams; the benchmark gate decides instead.
- **Do nothing.** The concurrency PR makes the two stream types generic and promise-based but leaves the other 14 shapes, each needing its own promise conversion anyway.

## Decisions (Chinmay, 2026-11-03)

1. `ReadStream`/`WriteStream` are opaque, implemented through `Source` and `Transform`; this replaces the interfaces in the concurrency API.
2. `stdout()`/`stderr()` are `WriteStream[String]`; `stdout_bytes()` shares their buffer.
3. `FetchResponse.body` stays buffered `Bytes`; streaming goes through `ClientResponse.body`.
4. Build it now, in parallel threads, after the concurrency runtime pieces it needs (`Promise`, I/O promises, `pipe`).

## Work split

1. **Core** (first, on top of the concurrency branch): this proposal into `proposals/`, with a skeptical review; opaque stream types and the native stream table; `Source`, `Transform`, `through` and its fusing; `streams.ms`; stdio, files and processes; the Rust deletions in the compiler and runtime; the line benchmark. It pushes the `io.ms` API early so the other two can start.
2. **Network and devices**: `Connection`, TLS, WebSocket, datagrams, HTTP exchange and client bodies, signals, file watcher, terminal events, ticker, and their native cleanup, including the same-thread placement rule.
3. **Formats and consumers**: JSON (absorbs `jsonstream.ms`), CSV, SSE, encoding, compression and tar, multipart, template `render_to`, log, checksum and digest, and the `ms-repo-check` rule.

Threads 2 and 3 branch from the core branch once its `io.ms` API is pushed. The three PRs merge in order: core, then the other two. Each PR includes its own codemod of call sites.
