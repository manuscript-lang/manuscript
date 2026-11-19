# Effects and concurrency

**Effects.** `// ms: allow_effect std.console.write` above a function permits what it reaches (also `std.fs.read|write`, `std.net.*`, `std.clock.read`, `std.env.read`, `std.random.read`); patterns `std.fs.*` work. Every function on the path to an effect needs its own line; `main`, tests and fixtures are exempt. Directives do not run effects. `ms verify` fails on lint warnings (`ms lint` alone does not).

**Promises.** `promise(fn: work())` starts a Result-returning callback; `.wait()` takes the result once (errors: `EIO` fault, `ECANCELED`, `ETIMEDOUT`, `EBADF` already waited). Dropping unfinished work cancels it. Options: `promise(fn: ..., options: PromiseOptions(timeout: ..., cancel: sw.signal()))` from `@std/concurrency/promise.ms`; `sw := cancel_switch()`; take `sw.signal()` before a closure that captures `sw`.

<!-- complete: concurrency.ms -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import from_list, map, collect from "@std/io/streams.ms"

fn work() Int!: ok(21)

fn main() Void!:
	pending := promise(fn: work())
	value := pending.wait()?
	output := from_list([value]) | map(fn x: x * 2) | collect(none)?
	if output.get_or(0, 0) != 42:
		return error(Error("unexpected output"))
```

- `wait_all` cancels the rest on the first failure. For every outcome, start promises in a List and `.wait()` each. Bound concurrency by batches. A pipe has one reader: it is not a worker pool.
- A promise closure that captures a String or record takes it: clone first, through a helper (`fn start(base: String, i: Int) Promise[Reply]`). `Promise` is imported separately from `promise`.
- **Pipes and streams.** `pipe[T](capacity)` (`@std/io/io.ms`) gives `reader()` and `writer()`; each producer takes its own `p.writer()` (a writer cannot be cloned). A worker takes the reader as a `var` parameter: `for x in rx:`. `from_list`, `lines`, `map`, `filter`, `collect` are in `@std/io/streams.ms`; `next()` returns `T?!`; transformations are lazy; `collect(none)` is unbounded. `flush()?` a `WriteStream` before scope end.
- Timestamps and Durations move like records (`.clone()`); compare with `a.compare(b) > 0`; `Timestamp.difference` and `shift` return Results. `HttpHeaders.append` returns a Result. `FetchOptions(timeout: milliseconds(n))` from `@std/net/fetch.ms`. Raw bytes: `text.to_bytes()`, `bytes.decode_utf8()`.
