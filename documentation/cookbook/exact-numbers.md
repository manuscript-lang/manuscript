+++
title = "Exact numbers"
weight = 10
+++

# Exact numbers

`Int` faults on overflow and `Float` rounds. When neither is acceptable, use an arbitrary-precision integer or an exact fraction.

## Numbers beyond Int

Save as `big.ms`. `BigInt` never overflows. Both operands of an operator must be `BigInt`, so convert an `Int` with `big_int_of_int`. `BigRat` is an exact fraction in lowest terms: arithmetic uses named methods (`add`, `subtract`, `multiply`, `divide`), never rounds, and two equal values compare equal. `to_fixed(digits)` rounds only when you ask for text.

<!-- manuscript-example: {"mode":"run","stdout":"15511210043330985984000000\n1\n0.30\n"} -->
```manuscript
import (
    parse_rat from "@std/math/big.ms",
    BigInt, big_int_of_int from "@std/math/math.ms",
)

fn factorial(n Int) BigInt {
    var total = big_int_of_int(1)
    for i in 2..n + 1 {
        total *= big_int_of_int(i)
    }
    return total
}

fn main() Void! {
    print(factorial(25).to_string())

    third := parse_rat("1/3")?
    sum := third.add(third).add(third)
    print(sum.to_string())

    tenth := parse_rat("1/10")?
    total := tenth.add(parse_rat("2/10")?)
    print(total.to_fixed(2)?)
}
```

- `25!` does not fit in `Int` (the limit is about 9.2e18); `BigInt` prints all 26 digits.
- Three thirds are exactly one. In `Float`, `0.1 + 0.2` is not `0.3`.
- `BigFloat` in the same module holds a chosen number of significant bits when you need roots or division without exact fractions.
- For money, `Decimal` (34 digits, explicit rounding) is usually the better fit: see [Numbers and booleans](../core-language/basics/numbers-and-booleans.md#decimal).
