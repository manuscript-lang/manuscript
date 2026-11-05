+++
title = "Promises"
weight = 1
+++

# Promises

Cancel pending work and inspect its promise’s result. Manuscript is in alpha; syntax and APIs evolve.

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

- Wait takes one result. Set deadlines through `PromiseOptions` at construction or `.with`.
- Cancellation acts at waits; CPU loops must cooperate. Dropping unfinished work cancels and joins.

Next: [Promise/Cancel APIs](../../standard-library/reference/concurrency/promise.ms.md), [streams](streams.md) and [shielded cleanup](../cleanup/cleanup-faults.md).
