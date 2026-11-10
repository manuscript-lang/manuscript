+++
title = "Testing and shipping"
weight = 8
+++

# Testing and shipping

The invoice rules are the part where a mistake costs money, so they get tests. A `test` block sits in the same file as the code, and `ms test` runs it.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript {filename="totals.ms"}
import expect_equal from "@std/test/test.ms"
import check, ints, lists from "@std/test/property.ms"

fn shipping(subtotal: Int) Int:
    if subtotal >= 4000:
        return 0
    return 500

fn order_total(prices: List[Int]) Int:
    let subtotal = prices.sum()
    return subtotal + shipping(subtotal)

test "small orders pay shipping":
    try expect_equal(order_total([1250, 800]), 2550)

test "big orders ship free":
    try expect_equal(order_total([2500, 2500]), 5000)

test "the order of items never changes the total":
    try check("any order", lists(ints(0, 5000), 0, 20), fn prices: expect_equal(order_total(prices.reversed()), order_total(prices)))
```

```text
RUN totals.ms::small orders pay shipping
PASS totals.ms::small orders pay shipping
RUN totals.ms::big orders ship free
PASS totals.ms::big orders ship free
RUN totals.ms::the order of items never changes the total
PASS totals.ms::the order of items never changes the total
3 tests, 0 failed
```

Save it as `totals.ms` and run `ms test totals.ms`.

## What to notice

- A test is a block with a name. `try expect_equal(actual, expected)` fails it on a mismatch and prints both values.
- The third test is a property test. `check` generates up to 100 lists of prices, runs the rule on each, and if one fails it shrinks it to a small counterexample with a seed you can replay.
- `ms test totals.ms --fuzz 30s` keeps generating fresh cases for 30 seconds per property, which turns the same test into a fuzzer.
- Properties describe what must always hold, so they find cases you would not think to write down.

## Ship it

`ms build` makes a native executable. Debug builds are quick and suit the edit-check-run loop. `ms build --build-type Release` optimizes for what you ship. The executable runs without Manuscript installed:

```sh
ms build ms.toml --build-type Release
```

`ms verify` runs the checker, the formatter check, lint and the tests and returns one result, which is the command to run before you share a change.

**Next:** [Working with an agent](working-with-an-agent.md). **Exact rules:** [Testing](../learn/testing.md), [Build levels](../developer-tooling/builds/build-levels.md).
