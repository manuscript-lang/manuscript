+++
title = "Pattern matching"
weight = 3
+++

# Pattern matching

Describe payment outcomes with one flat match. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::describe a payment\nPASS example.ms::describe a payment\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

enum Payment:
    Paid(receipt: String)
    Declined(reason: String)

fn describe(payment: Payment) String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"

test "describe a payment":
    let payment = Payment.Paid("receipt-42")
    try expect_equal(describe(payment), "Paid: receipt-42")
```

```sh
ms test example.ms
```

```text
RUN example.ms::describe a payment
PASS example.ms::describe a payment
1 tests, 0 failed
```

<a id="keep-match-flow-flat"></a>
<a id="matching-literals"></a>
<a id="arm-values"></a>
<a id="payload-patterns"></a>
<a id="exhaustiveness"></a>
<a id="optional-and-result-values"></a>
<a id="contract-type-patterns"></a>
<a id="matching-resource-references"></a>

- Cover every enum variant, or finish with `_`. Bind payloads in declaration order.
- Borrowed matches lend payloads; a last-use owned match can move them.

Next: [enums](../types/alternatives.md), [interfaces](../types/contracts.md) and [ownership](../types/references.md).
