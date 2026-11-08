[Wiki](../index.md) › [Runtime](index.md)

# Template numbers preserve exact JSON values

`JsonValue.NumberValue` retains decimal text. Converting template conditions to
Float makes `1e-400` false, merges neighboring large integers, and loses ordering
when exponents overflow. Truth, equality, ordering, `default`, and list `contains`
must agree on the same exact value.

Normalize a valid token into sign, coefficient with insignificant zeros removed,
and decimal order. Keep the order as signed decimal text: even the exponent need
not fit in an Int. Compare order then coefficient; never materialize powers of
ten or introduce Float, Decimal, or rational-parser range limits. Canonical Int
tokens can use exact machine-integer comparisons as a common-case fast path.

Regression coverage includes underflow, neighboring integers, equivalent decimal
forms, signed zero, negative order reversal, machine boundaries, and exponents
thousands of digits long. Numeric kind comes from the JSON variant, not whether
a Float conversion succeeds.
