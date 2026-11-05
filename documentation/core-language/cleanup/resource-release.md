+++
title = "Closing a resource"
weight = 2
+++

# Closing a resource

Usually, let [scope-end cleanup](scopes.md) close a file, socket or stream. Close explicitly when the next operation should begin only after the resource is released, or when you need to handle a close error.

Consider writing a report. There are three different questions: did the writer accept the data, did buffered data drain far enough for the destination's contract, and was the resource released? A successful `write` answers the first. An explicit `flush().wait()` lets you handle the second. Closing answers the third. Do not replace the first two checks with an assumption that scope exit means delivery succeeded.

Flush before closing when you need the destination to catch up or need to handle a flush failure:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import WriteStream from "@std/io/io.ms"

fn finish(var output: WriteStream[String]) Unit!:
    try output.flush().wait()
    return output.close()
```

`flush().wait()` follows the destination’s backpressure rule. File and socket streams wait for queued bytes to drain; a pipe waits until its queue is at or below `capacity`, which need not be empty. Closing a built-in pipe writer releases that writing end without waiting for the reader. A custom sink supplies its own close behavior and may wait. The owner still performs its scope-end close, which is harmless because close is idempotent.

Choose the operation that confirms your work: `close()` returns a `Result` and a failed scope-end close is returned or faults; explicit commit, finish, or flush operations report expected errors with `Result`. A value that is not a resource, such as a `List[Int]` or a closure that captures none, adds no close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery, and a binding registers its close right after the initializer succeeds, before cancellation can unwind it. See [Closeable](closeable.md).
