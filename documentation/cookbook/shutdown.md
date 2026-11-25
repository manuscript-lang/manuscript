+++
title = "Stopping cleanly"
weight = 20
+++

# Stopping cleanly

Finish the current work and release resources when the process is asked to stop with Ctrl-C or `kill`.

## Wait for a stop signal

Save as `stop.ms`. `watch_signals` turns signals into a stream of numbers. The program waits for the first one, and then leaves `main` normally, so every value in scope is cleaned up as on any other exit. The example prints `ready` once the signal is registered, so a supervisor or a test knows it is safe to send one.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import watch_signals from "@std/os/process.ms"

type Worker {
    name String
}

fn move Worker.close() Void! {
    print(f"{self.name} stopped")
    return ok()
}

fn main() Void! {
    var signals = watch_signals([2, 15])?
    _worker := Worker(name: "worker")
    print("ready")

    _signal := signals.next()?
    print("stopping")
    return ok()
}
```

```sh
ms run stop.ms
```

Press Ctrl-C and the output ends with:

```text
stopping
worker stopped
```

- Signals 2 and 15 are SIGINT and SIGTERM, which Ctrl-C and `kill` send.
- A type with a `close` method is cleaned up when its scope ends, in reverse order of creation, however the scope ends.
- A server needs none of this: `serve(...).wait()` already stops on SIGINT and SIGTERM, drains open connections within the grace period, and then returns ([HTTP server](../core-language/concurrency/http-server.md)).
