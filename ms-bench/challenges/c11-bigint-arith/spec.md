# Big integer arithmetic

Each non-blank input line (blank means empty or only spaces) has the form `<op> <A> <B>`: three tokens
separated by single spaces. It produces one output line.

- `op` is `add`, `sub` or `mul` (case-sensitive). `A` and `B` are non-negative integers written as one or
  more ASCII digits; they have no sign, may have leading zeros, and are far too long for 64-bit integers
  (tests use up to 500 digits for `add` and `sub`, up to 200 digits for `mul`).
- Output the exact result in decimal: `A + B`, `A - B` (which may be negative, written with a leading `-`),
  or `A * B`. No leading zeros, and zero is written `0` (never `-0`).

Errors, checked in this order:

1. A line that does not have exactly three tokens, or whose `op` is not one of the three: `error: bad command`
2. Either operand is not made only of ASCII digits (this includes an empty token, as in `add  5`):
   `error: bad number`

Example input:

    add 999999999999999999999 1
    sub 5 12
    mul 123456789123456789 987654321987654321
    add 007 0000
    add 12 x
    div 4 2
    sub 100

Output:

    1000000000000000000000
    -7
    121932631356500531347203169112635269
    7
    error: bad number
    error: bad command
    error: bad command
