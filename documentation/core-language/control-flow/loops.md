+++
title = "Loops"
weight = 2
+++

# Loops

Trace bounds and updates to review which iterations run; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::sum selected indexes\nPASS example.ms::sum selected indexes\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import range_by from "@std/collections/collections.ms"
import expect_equal from "@std/test/test.ms"

test "sum selected indexes":
    var total = 0
    for index in 0..5:
        total += index
    try expect_equal(total, 10)

    let descending = try range_by(start: 5, end: 0, step: -2)
    try expect_equal(descending, [5, 3, 1])
    var remaining = 3
    while remaining > 0:
        remaining -= 1
    try expect_equal(remaining, 0)
```

```sh
ms test example.ms
```

```text
RUN example.ms::sum selected indexes
PASS example.ms::sum selected indexes
1 tests, 0 failed
```

<a id="traversing-a-list"></a>
<a id="counting-loops"></a>
<a id="stepped-ranges"></a>
<a id="iterable-types-and-binding"></a>
<a id="iterators"></a>
<a id="borrowing-containers"></a>
<a id="repeating-while-a-condition-holds"></a>
<a id="exiting-an-iteration"></a>
<a id="cancellation"></a>

- `0..5` excludes 5; `range_by` supports negative steps and returns a Result.
- `break` exits the nearest loop; `continue` starts its next iteration. Both close resources in the scope they leave.

Next: [iteration APIs](../../standard-library/reference/collections/collections.ms.md), [borrowing](../types/references.md) and [CPU-loop cancellation](../concurrency/promises.md#cancellation).
