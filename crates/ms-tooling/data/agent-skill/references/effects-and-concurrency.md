# Effects, promises and streams

Effects are linted. Put a narrow directive such as `// ms: allow_effect std.console.write` above a printing function, or pass a capability. Directives do not execute effects.

No async/await keywords. `promise` schedules a Result-returning callback; `.wait()` takes its result once. Dropping unfinished work cancels and joins. Borrowed captures must outlive the work and remain unmodified while borrowed.

<!-- complete: concurrency.ms -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import from_list, map, collect from "@std/io/streams.ms"

fn work() Int!: ok(21)

fn main() Unit!:
	pending := promise(fn: work())
	value := pending.wait()?
	output := from_list([value]) | map(fn x: x * 2) | collect(none)?
	if output.get(0, 0) != 42:
		return error(Error("unexpected output"))
```

Import PromiseOptions from `"@std/concurrency/promise.ms"`; set `promise(..., options: PromiseOptions(timeout: duration))`, never a wait argument.

`from_list`, `lines`, `map`, `collect`: `"@std/io/streams.ms"`. `pipe`: `"@std/io/io.ms"`. `pipe[T](capacity)` coordinates producers/consumers; keep mutable state with one owner.

Stream `.next()` returns T?!: Result of Optional, none at EOF. `for item in stream:` extracts items and propagates errors; use a Result-returning function. Writes return Unit! and wait when full. Transformations pull lazily; closing them closes their input. `collect(none)` is unlimited; bound potentially unbounded inputs.
