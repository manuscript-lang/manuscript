+++
title = "Watching files"
weight = 4
+++

# Watching files

React when files change: rebuild, reload a configuration, or process files dropped into a folder.

## Wait for a change

Save as `watch_test.ms` and run `ms test watch_test.ms`. `watch` returns a stream of `FileEvent` values, each with the `path` that changed and a `kind` of `"change"` or `"rename"` (which covers a file appearing or disappearing). Reading with `next(timeout: ...)` fails instead of waiting forever when nothing happens.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import (
    temporary, watch, write_file from "@std/os/fs.ms",
    expect_equal from "@std/test/test.ms",
    seconds from "@std/time.ms",
)

test "a new file is reported" {
    dir := temporary("watch-")?
    var events = watch(dir.path())?
    write_file(f"{dir.path()}/note.txt", "hello").wait()?

    event := events.next(timeout: seconds(10))?
    expect_equal(event.get().path.ends_with("note.txt"), true)?
}
```

```text
RUN watch_test.ms::a new file is reported
PASS watch_test.ms::a new file is reported
1 tests, 0 failed
```

`temporary` returns a directory that removes itself and its contents when it is closed.

## Re-read a file when it changes

Save as `reload.ms`. This program re-reads a file each time it changes and stops when the watched path is removed.

Pass `recursive: true` to watch a whole tree. Pass `WatchOptions(interval: ...)` to poll instead of using operating-system events, for example on a network drive.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import (
    arguments from "@std/os/env.ms",
    read_file, watch from "@std/os/fs.ms",
)

fn main() Void! {
    path := arguments().get_or(0, "config.json")
    var events = watch(path)?

    for event in events {
        read := read_file(event.path).wait()
        if read.is_error() and read.err().kind == "ENOENT" {
            continue
        }

        text := read?
        print(f"{event.path} changed, {text.length()} bytes")
    }

    return ok()
}
```

```sh
ms run reload.ms -- config.json
```

- A path removed before it is read is skipped, and the stream then ends.
- One edit can produce several events. Treat an event as "look again", and read the file rather than relying on the event's kind.
- The stream ends when the watched root is removed or moved, so a `for` loop over it finishes instead of waiting forever.
