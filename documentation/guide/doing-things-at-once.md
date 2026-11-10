+++
title = "Doing things at once"
weight = 6
+++

# Doing things at once

Orders arrive as one file per day. Reading them one after another wastes time when each read waits on the disk. In Manuscript a function that waits is an ordinary function, so there is no `async` to add. A call that waits returns a `Promise`, and you can start several before you collect any.

<!-- manuscript-example: {"mode":"run","files":{"a.csv":"1,Sam,1250\n","b.csv":"2,Ada,4000\n3,Lin,900\n"},"stdout":"3 rows from 2 files\n"} -->
```manuscript {filename="rows.ms"}
import read_file from "@std/os/fs.ms"
import wait_all from "@std/concurrency/promise.ms"

fn count_rows(text: String) Int:
    return text.split("\n").filter(fn line: not line.is_empty()).length()

fn run(paths: List[String]) Int!:
    reads := paths.map(fn path: read_file(path))
    files := try wait_all(reads)
    var rows = 0
    for file in files:
        text := try file.decode_utf8().ok_or(Error("not UTF-8", kind: "EBADMSG"))
        rows += count_rows(text)
    return ok(rows)

fn main() Unit!:
    rows := try run(["a.csv", "b.csv"])
    print("{rows} rows from 2 files")
```

```text
3 rows from 2 files
```

Save it as `rows.ms`, with `a.csv` and `b.csv` beside it, and run `ms run rows.ms`.

## What to notice

- `read_file(path)` returns a `Promise` that is already running. `paths.map(...)` starts both reads, and `wait_all` collects the results in order.
- Nothing is marked `async`. `run` is a plain function that happens to wait.
- The first failure wins. If a file is missing, `wait_all` returns that error and cancels the reads still in flight.
- A promise that is dropped before it finishes is cancelled, and its work ends before the values it uses go away. Work never outlives its owner.
- Cancellation arrives at the next wait, and cleanup runs as it does on any other exit.

## Sharing data

A promise reads what it captures and cannot change it. When several tasks need to update one value, give that value one owner and send it messages through a [pipe](../core-language/concurrency/streams.md#pipes). Ownership is the reason there is no data race to guard against.

**Next:** [Organizing code](organizing-code.md). **Exact rules:** [Promises](../core-language/concurrency/promises.md), [Streams and pipes](../core-language/concurrency/streams.md).
