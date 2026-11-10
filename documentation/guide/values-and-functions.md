+++
title = "Values and functions"
weight = 1
+++

# Values and functions

A billing tool needs an invoice: add up the line items, add shipping unless the order is big enough, and print money like a person would. Here is the whole program.

<!-- manuscript-example: {"mode":"run","stdout":"Subtotal: 45.50\nShipping: 0.00\nTotal: 45.50\nItems under 10.00 after discount: 1\n"} -->
```manuscript {filename="invoice.ms"}
fn line_total(price: Int, quantity: Int = 1) Int:
    return price * quantity

fn shipping(subtotal: Int) Int:
    if subtotal >= 4000:
        return 0
    return 500

fn money(cents: Int) String:
    rest := cents % 100
    pad := if rest < 10: "0" else: ""
    return "{cents / 100}.{pad}{rest}"

fn main() Unit:
    prices := [1250, 800, 2500]
    var subtotal = 0
    for price in prices:
        subtotal += line_total(price)
    discounted := prices.map(fn price: price - 200)
    cheap := discounted.filter(fn price: price <= 1000)
    total := subtotal + shipping(subtotal)
    print("Subtotal: {money(subtotal)}")
    print("Shipping: {money(shipping(subtotal))}")
    print("Total: {money(total)}")
    print("Items under 10.00 after discount: {cheap.length()}")
```

```text
Subtotal: 45.50
Shipping: 0.00
Total: 45.50
Items under 10.00 after discount: 1
```

Save it as `invoice.ms` and run `ms run invoice.ms`.

## What to notice

- `:=` names a value and `var` names one that changes. `subtotal` is a `var` because the loop adds to it; everything else is a `:=`. Types are inferred, so you rarely write them.
- A function declares its parameter types and its result type after the parameter list. `quantity: Int = 1` is a default, so `line_total(price)` works without the second argument.
- `if` works as a statement and as an expression: `pad := if rest < 10: "0" else: ""` picks a value.
- `{expression}` inside a string interpolates any expression, including a function call.
- A function is a value. `prices.map(fn price: price - 200)` passes a function to `map`, and `filter` keeps the items for which a function returns `true`. `prices` itself does not change.
- Four spaces open a block. There are no braces and no semicolons.

## Try it

Change the free-shipping threshold in `shipping` to `5000` and run again. The total grows by the shipping cost.

**Next:** [Data](data.md). **Exact rules:** [Bindings](../core-language/basics/bindings.md), [Functions](../core-language/functions/_index.md).
