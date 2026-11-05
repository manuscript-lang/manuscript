+++
title = "Promises"
weight = 1
+++

# Promises

Inspect cancellation to review how pending work stops; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::cancel pending work\nPASS example.ms::cancel pending work\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import cancel_switch, PromiseOptions from "@std/concurrency/promise.ms"
import sleep from "@std/os/time.ms"
import expect_equal, expect_error from "@std/test/test.ms"

test "cancel pending work":
    let stop = cancel_switch()
    let pending = sleep(1.seconds()).with(
        options: PromiseOptions(cancel: stop.signal())
    )
    stop.cancel()
    let cause = try expect_error(pending.wait())
    try expect_equal(cause.kind, "ECANCELED")
```

```sh
ms test example.ms
```

```text
RUN example.ms::cancel pending work
PASS example.ms::cancel pending work
1 tests, 0 failed
```

<a id="waiting"></a>
<a id="cancellation"></a>
<a id="reading-and-changing-shared-values"></a>
<a id="faults"></a>
<a id="threads"></a>

- Wait takes one result; set `PromiseOptions` deadlines at construction or `.with`.
- Cancellation needs waits or signal checks; drop cancels and joins unfinished work.

Next: [Promise API](../../standard-library/reference/concurrency/promise.ms.md#promise) and [signal checks](../../standard-library/reference/concurrency/promise.ms.md#signalcancelled), [streams](streams.md) and [shielded cleanup](../cleanup/cleanup-faults.md).
