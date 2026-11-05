+++
title = "Programming faults"
weight = 3
+++

# Programming faults

Assert an invariant failure to review faults separately from expected errors; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::check an invariant failure\nPASS example.ms::check an invariant failure\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import panic from "@std/core.ms"
import expect_equal, expect_fault from "@std/test/test.ms"

fn require_positive(value: Int) Unit:
    if value <= 0:
        panic("Expected a positive value")

test "check an invariant failure":
    let report = try expect_fault(fn: require_positive(0))
    try expect_equal(report.contains("Expected a positive value"), true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::check an invariant failure
PASS example.ms::check an invariant failure
1 tests, 0 failed
```

<a id="invariant-checks"></a>
<a id="explicit-faults"></a>
<a id="faults-the-checker-rejects"></a>
<a id="runaway-recursion"></a>
<a id="cleanup-and-observation"></a>

- `try` cannot catch faults. Use Results for expected failures.
- Checked faults run cleanup. Promises report them as `EIO`; unhandled process faults end the program.

Next: [cleanup faults](../cleanup/cleanup-faults.md), [fault assertions](../../standard-library/reference/test/test.ms.md#expect_fault) and [runtime boundaries](../../contributing/runtime-conventions.md).
