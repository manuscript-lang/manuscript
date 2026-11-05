+++
title = "Declarations and calls"
weight = 1
+++

# Declarations and calls

Named inputs and explicit results make a function easy to review; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::clear call arguments\nPASS example.ms::clear call arguments\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn subtract(amount: Int, deduction: Int = 1) Int:
    return amount - deduction

test "clear call arguments":
    try expect_equal(subtract(5), 4)
    try expect_equal(subtract(5, 2), 3)
    try expect_equal(subtract(deduction: 2, amount: 5), 3)
```

```sh
ms test example.ms
```

```text
RUN example.ms::clear call arguments
PASS example.ms::clear call arguments
1 tests, 0 failed
```

- Named functions declare parameter and result types; `try` propagates an error to the caller.
<span id="argument-names"></span><span id="default-arguments"></span>

- Unlabeled arguments fill the first unfilled parameter; defaults evaluate for omitted arguments at each call.

<span id="collections-as-arguments"></span>

## Collection parameters

<!-- manuscript-example: {"mode":"test","stdout":"RUN total.ms::one list argument\nPASS total.ms::one list argument\n1 tests, 0 failed\n"} -->
```manuscript {filename="total.ms"}
import expect_equal from "@std/test/test.ms"

fn total(values: List[Int]) Int:
    var result = 0
    for value in values:
        result += value
    return result

test "one list argument":
    let prices = [12, 8, 25]
    try expect_equal(total(prices), 45)
    try expect_equal(total([]), 0)
    try expect_equal(prices.length(), 3)
```

```sh
ms test total.ms
```

```text
RUN total.ms::one list argument
PASS total.ms::one list argument
1 tests, 0 failed
```

- The list is one required argument, even when empty.
- Reading through a borrowed parameter leaves the caller’s list available.

<span id="declarations-and-resolution"></span><span id="evaluation-order"></span><span id="unit-and-never"></span><span id="calls-that-block"></span>

Next: [call checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/calls.rs); [function values and closures](function-values-and-closures.md).
