[Wiki](../index.md) › [Runtime](index.md)

# Template numbers preserve exact JSON values

`JsonValue.NumberValue` retains decimal text. Converting template conditions to
Float makes `1e-400` false, merges neighboring large integers, and loses ordering
when exponents overflow. Truth, equality, ordering, `default`, and list `contains`
must agree on the same exact value.

Keep validated coefficient bytes with a significant span and a decimal-order
offset. Ordinary values without exponents compare offsets directly. Normalize
signed decimal order only for exponent-bearing comparisons: even the exponent
need not fit in an Int. Compare order then coefficient, treating trailing zeros
as insignificant; never expand powers of ten or impose conversion range limits.
Canonical Int tokens can use exact machine-integer comparisons.

Avoid normalizing every coefficient eagerly. Different first significant digits
already decide coefficient order; shared prefixes use native string comparison
after lazy normalization. A source-level byte-at-a-time comparison regresses long
shared prefixes. Keep ordinary, equivalent, negative, extreme-exponent and long
coefficient controls alongside integer performance checks.

Regression coverage includes underflow, neighboring integers, equivalent decimal
forms, signed zero, negative order reversal, machine boundaries, and exponents
thousands of digits long. Numeric kind comes from the JSON variant, not whether
a Float conversion succeeds.
