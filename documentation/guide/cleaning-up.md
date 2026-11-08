+++
title = "Cleaning up"
weight = 5
+++

# Cleaning up

Files, sockets and processes need closing, even when the function leaves early because something failed. In Manuscript you do not write the close. A value that owns a resource closes it when its scope ends.

<!-- manuscript-example: {"mode":"run","files":{"orders.csv":"id,customer,cents\n1,Sam,1250\n2,Ada,4000\n"},"stdout":"2 orders\n","cases":[{"files":{"orders.csv":""},"stdout":"orders.csv is empty\n","exit_code":1}]} -->
```manuscript {filename="count.ms"}
import open from "@std/os/fs.ms"
import lines, collect from "@std/io/streams.ms"

fn count_orders(path: String) Int!:
    let file = try open(path)
    let rows = try collect(try file.reader() | lines)
    if rows.length() == 0:
        return error(Error("{path} is empty", kind: "EBADMSG"))
    return ok(rows.length() - 1)

export fn main() Int:
    let count = count_orders("orders.csv")
    if count.is_error():
        print(count.err().message)
        return 1
    print("{count.get()} orders")
    return 0
```

```text
2 orders
```

Run it next to an `orders.csv` file containing a header and two rows. With an empty `orders.csv`, it prints `orders.csv is empty` and exits with 1.

## What to notice

- `open` returns a file handle. Binding it with `let file` is all it takes: the handle closes when `count_orders` returns, on the normal path and on every `try` or `return error(...)` before it.
- If `open` itself fails, there is nothing to close and the error goes to the caller.
- Cancellation and runtime faults close it as well. You cannot forget a close by returning early.
- Scopes nest. Inner resources close before outer ones, and in one scope the last declared closes first.

## When you need to close early

Declare the binding with `var` and call `close()` when you are done reading but not yet done with the function. A second close is harmless:

```manuscript
var file = try open(path)
let head = try file.read_lines(max_lines: 1)
let _ = file.close()
slow_work(head)
```

`close()` returns a `Result`, because closing can fail. Flush output before you close it so delivery errors reach you: `try output.flush()`. `ms lint` warns when a scope-closed resource has an uncalled `flush`.

**Next:** [Doing things at once](doing-things-at-once.md). **Exact rules:** [Scope-end cleanup](../core-language/cleanup/scopes.md).
