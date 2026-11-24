# Effects, promises and streams

Effects are linted. Put a narrow directive such as `// ms: allow_effect std.console.write` above a printing function, or pass a capability. Directives do not execute effects.

No async/await keywords. `promise` schedules a Result-returning callback; `.wait()` takes its result once. Dropping unfinished work cancels and joins. Borrowed captures must outlive the work and remain unmodified while borrowed.

<!-- complete: concurrency.ms -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import from_list, collect from "@std/io/streams.ms"
import map from "@std/io/steps.ms"

fn work() Int!: ok(21)

fn main() Void!:
	pending := promise(fn: work())
	value := pending.wait()?
	output := from_list([value]) | map(fn x: x * 2) | collect(null)?
	if output.get_or(0, 0) != 42:
		return error(Error("unexpected output"))
```

Import PromiseOptions from `"@std/concurrency/promise.ms"`; set `promise(..., options: PromiseOptions(timeout: duration))`, never a wait argument.

`from_list`, `collect`: `"@std/io/streams.ms"`. `lines`, `map`: `"@std/io/steps.ms"`. `pipe`: `"@std/io/io.ms"`. `pipe[T](capacity)` coordinates producers/consumers; keep mutable state with one owner.

Stream `.next()` returns T?!: Result of Optional, null at EOF. `for item in stream:` extracts items and propagates errors; use a Result-returning function. Writes return Void! and wait when full. Transformations pull lazily; closing them closes their input. `collect(null)` is unlimited; bound potentially unbounded inputs.

`wait_all` cancels the rest on the first failure. To collect every outcome (for example one result per URL), start the promises in a List and `.wait()` each in turn; the outcome of each is a Result you can store. For bounded concurrency, work in batches of N: start N promises, wait them, start the next N. A pipe has one reader, so it is not a worker pool. A timeout set by `PromiseOptions(timeout:)` surfaces as an error whose `kind` is `ETIMEDOUT`; `kind` is `String?`, so compare `e.kind.get_or("")`. Read a Result's error with `r.err()`.

Each producer needs its own handle: give every `promise(fn: ...)` closure `p.writer()`, not the shared `p` (a closure that captures `p` takes it away). Cancel with `sw := cancel_switch()` and `promise(fn: ..., options: PromiseOptions(cancel: sw.signal()))`; a cancelled `wait()` reports `ECANCELED`. Time values (`Timestamp`, `Duration`) move like records: `.clone()` to reuse one; compare durations with `a.compare(b) > 0`. Flush every `WriteStream` with `flush()?` before its scope ends. `ms verify` fails on lint warnings (`ms lint` alone does not): every function that reaches an effect, including each caller on the way (`std.fs.read`, `std.fs.write`, `std.clock.read`), needs its own `// ms: allow_effect` line. Raw bytes: there is no `b""` literal; use `text.to_bytes()` and `bytes.decode_utf8()`, which is `String?`.

A `promise` closure that captures a String or record takes it away: clone before the closure, through a helper such as `fn start(base String, i Int) Promise[Reply]` called as `.map(fn i: start(base.clone(), i))`. `Promise` (the type) is imported separately from `promise`. `HttpHeaders.append` returns a Result: use `?`. A per-request timeout is `FetchOptions(timeout: milliseconds(n))` from `@std/net/fetch.ms`. A `serve` handler cannot hold state, so to test retries have the client send a header such as `x-attempt` and make the handler answer from it.

A worker takes a pipe reader as a `var` parameter and reads it with `for x in rx:`; do not move it into a pipeline or capture it. A writer cannot be cloned: call `pipe.writer()` again for another handle. Take `inner := sw.signal()` before the closure that captures `sw`, then pass `inner` in the options. `Timestamp.difference` and `shift` return Results: use `?`. A Closeable record can hold a stream and write its closing event in `close`; a binding named `_g` still closes at scope end.
