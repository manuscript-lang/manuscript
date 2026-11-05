+++
title = "Cleanup failures"
weight = 5
+++

# Cleanup failures

Fail during cleanup to review which fault remains primary; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::keep the original fault\nPASS example.ms::keep the original fault\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import Closeable, panic from "@std/core.ms"
import expect_equal, expect_fault from "@std/test/test.ms"

type BrokenCleanup:
    closed: Bool = false

impl Closeable for BrokenCleanup:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            panic("cleanup failed")
        return ok(unit)

fn work() Unit:
    let _resource = BrokenCleanup()
    panic("work failed")

test "keep the original fault":
    let report = try expect_fault(fn: work())
    try expect_equal(report.contains("work failed"), true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::keep the original fault
PASS example.ms::keep the original fault
1 tests, 0 failed
```

<a id="if-close-itself-faults"></a>
<a id="cleanup-can-outlast-a-timeout"></a>

- An existing fault stays primary. Otherwise the first cleanup fault becomes primary; later faults are secondary, and remaining cleanup is attempted.
- Cleanup is shielded from cancellation and deadlines. It can wait beyond the original timeout.

Next: [close Results](closeable.md#a-close-returns-a-result), [cancellation](../concurrency/promises.md#cancellation) and [shutdown escalation](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt/src/start.rs#L34-L66).
