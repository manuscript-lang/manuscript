+++
title = "Numbers and booleans"
weight = 3
+++

# Numbers and booleans

Numeric types make precision, conversion and failure visible in a review; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::checked numeric boundaries\nPASS example.ms::checked numeric boundaries\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "checked numeric boundaries":
    let quantity: Int8 = 12
    let total = quantity.to_int() * 3
    let narrow = try total.to_int8().ok_or(Error("quantity too large"))
    try expect_equal(narrow, 36)
    try expect_equal(total > 0, true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::checked numeric boundaries
PASS example.ms::checked numeric boundaries
1 tests, 0 failed
```

- Numeric kinds do not widen implicitly; narrowing conversions return `T?` when the value may not fit.
<span id="runtime-numeric-outcomes"></span><span id="int"></span><span id="float"></span>

- Integer overflow/division by zero fault; Float overflow gives infinity and invalid arithmetic gives NaN. Decimal overflow/division by zero fault.

## Decimal

<!-- manuscript-example: {"mode":"test","stdout":"RUN invoice.ms::round an invoice\nPASS invoice.ms::round an invoice\n1 tests, 0 failed\n"} -->
```manuscript {filename="invoice.ms"}
import Decimal from "@std/math/decimal.ms"
import expect_equal, expect_error from "@std/test/test.ms"

test "round an invoice":
    let subtotal = 19.99d * 3d
    let tax = try (subtotal * 0.0825d).round(places: 2)
    let text = try (subtotal + tax).to_fixed(digits: 2)
    try expect_equal(text, "64.92")
    let cause = try expect_error(subtotal.to_fixed(-1))
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test invoice.ms
```

```text
RUN invoice.ms::round an invoice
PASS invoice.ms::round an invoice
1 tests, 0 failed
```

- Round the amount deliberately; formatting preserves the requested trailing zeros.
- Invalid places/digits return EINVAL; an unrepresentable rounded Decimal returns ERANGE.

## Durations

<!-- manuscript-example: {"mode":"test","stdout":"RUN interval.ms::name an elapsed span\nPASS interval.ms::name an elapsed span\n1 tests, 0 failed\n"} -->
```manuscript {filename="interval.ms"}
import expect_equal from "@std/test/test.ms"

test "name an elapsed span":
    let interval = 2.seconds() + 500.milliseconds()
    try expect_equal(interval.to_milliseconds(), 2500)
    try expect_equal("{interval}", "2.5s")
```

```sh
ms test interval.ms
```

```text
RUN interval.ms::name an elapsed span
PASS interval.ms::name an elapsed span
1 tests, 0 failed
```

- Duration is signed nanoseconds with checked arithmetic; use monotonic clock readings for elapsed time.
- Instant comparisons require one clock domain; cross-domain operations fault.

<span id="arithmetic-and-conversion"></span><span id="sized-numbers"></span><span id="numeric-conversion"></span><span id="scale-rounding-and-fixed-places"></span><span id="bigint"></span><span id="booleans"></span>

Next: [numeric APIs](../../standard-library/reference/math/math.ms.md) and [Decimal rounding](../../standard-library/reference/math/decimal.ms.md); [strings and bytes](text-and-bytes.md).
