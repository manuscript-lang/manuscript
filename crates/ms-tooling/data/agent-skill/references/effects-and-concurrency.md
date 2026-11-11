# Effects, promises and streams

Effects are linted. Put a narrow directive such as `// ms: allow_effect std.console.write` above the function that prints. A directive declares permission for linting; it does not execute the operation. A capability can instead be passed explicitly.

There are no async/await keywords. `promise` schedules a callback returning a Result; `p.wait()` returns its result once. Dropping unfinished work cancels and joins it. Borrowed captures must outlive the work and cannot be mutated while borrowed.

Save as `concurrency.ms`:

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

`ms run concurrency.ms` prints nothing and exits 0.

- For a timeout, import `PromiseOptions` from `"@std/concurrency/promise.ms"` and configure `promise(..., options: PromiseOptions(timeout: duration))`. `wait()` takes no timeout argument.
- `from_list`, `lines`, `map`, `collect` come from `"@std/io/streams.ms"`; `pipe` comes from `"@std/io/io.ms"`. Use `pipe[T](capacity)` to coordinate producers and consumers; keep mutable state with one owner.

`stream.next()` returns `T?!`: a Result containing an Optional item, with `none` at end-of-stream. `for item in stream:` obtains payloads and propagates read errors, so use a compatible Result-returning function. Writes return `Unit!`. Writes wait when full; lazy transformations pull on demand. `collect(none)` collects without an item limit; provide a limit for potentially unbounded input. Closing a transformed stream closes its input.
