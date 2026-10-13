# Expression simplifier

Each non-blank input line is one algebraic expression written as an S-expression. For each line, print the
fully simplified expression in canonical form, or `error: syntax`. A line that is empty or only spaces and
tabs produces no output.

## Syntax

An expression is an *atom* or a parenthesised form `(HEAD ARG ...)`.

- Integer atom: optional `-` then one or more ASCII digits (`007` is 7, `-0` is 0). Value of an integer is
  a signed 64-bit number; tests keep every number they read or compute within +/-10^15.
- Variable atom: a lowercase letter followed by lowercase letters, digits or `_` (`x`, `foo_2`). Any such
  word is a variable when it appears as an atom, including `neg`.
- Forms (the head must be exactly one of these words and is never an expression itself):

| form | meaning |
| --- | --- |
| `(+ A B)` | sum |
| `(- A B)` | difference `A - B` |
| `(* A B)` | product |
| `(neg A)` | negation |
| `(^ A N)` | power; `N` must be a plain atom of ASCII digits only (no sign, not a form), e.g. `(^ x 3)` |

Tokens are separated by runs of spaces and tabs, and parentheses are tokens on their own, so
`(+(* 1 x)(* y 1))` is valid. Anything else is `error: syntax`: wrong argument counts, unknown heads, empty
`()`, unbalanced parentheses, extra tokens after the expression, a token that is neither integer nor
variable (`1.5`, `+5`, `X`, `x-1`, `1x`, a lone `-`), or an exponent that is not digits. The whole line
must be exactly one expression.

## Simplification

`simplify(e)` works bottom-up: first simplify the children of `e`, then try the rules for the root, in the
order listed. The first rule whose condition matches rewrites the root; the **replacement is then
simplified again from scratch with the same procedure** (children first, then rules), and that result is the
answer. If no rule matches, the node is returned as is. Atoms are already simplified.

`a == b` below means structural equality of the two (already simplified) subexpressions. `Num k` is an
integer, and `Num 0`, `Num 1`, `Num -1`, `Num 2` mean those specific values. `n` and `m` are the exponents.

**`(+ l r)`**

1. `l` and `r` are both numbers: their sum.
2. `l == 0`: `r`.
3. `r == 0`: `l`.
4. `l == r`: `(* 2 l)`.
5. `r` is `(neg x)`: `(- l x)`.
6. `l` is `(neg x)`: `(- r x)`.

**`(- l r)`**

1. both numbers: the difference.
2. `r == 0`: `l`.
3. `l == 0`: `(neg r)`.
4. `l == r`: `0`.
5. `r` is `(neg x)`: `(+ l x)`.

**`(* l r)`**

1. both numbers: the product.
2. `l == 0` or `r == 0`: `0`.
3. `l == 1`: `r`.
4. `r == 1`: `l`.
5. `l == -1`: `(neg r)`; `r == -1`: `(neg l)` (in that order).
6. `l == r`: `(^ l 2)`.
7. `r` is a number (and `l` is not): `(* r l)`; constants move to the left.
8. `l` and `r` are both `neg` forms `(neg x)`, `(neg y)`: `(* x y)`. Otherwise `l` is `(neg x)`:
   `(neg (* x r))`. Otherwise `r` is `(neg y)`: `(neg (* l y))`.
9. `l` is `(^ x a)`, `r` is `(^ y b)` and `x == y`: `(^ x a+b)`.
10. `l` is `(^ x a)` and `r == x`: `(^ x a+1)`.
11. `r` is `(^ y b)` and `l == y`: `(^ y b+1)`.

**`(neg x)`**

1. `x` is a number: its negation.
2. `x` is `(neg y)`: `y`.
3. `x` is `(- a b)`: `(- b a)`.

**`(^ b n)`**

1. `n == 0`: `1`.
2. `n == 1`: `b`.
3. `b` is a number `k`: `k` raised to `n`.
4. `b` is `(^ x m)`: `(^ x m*n)`.
5. `b` is `(neg x)`: `(^ x n)` if `n` is even, otherwise `(neg (^ x n))`.

Arithmetic never overflows in the tests (all computed numbers and all exponents, which stay at most 1000,
are small). The simplified tree is always a fixed point: simplifying it again changes nothing.

## Output

Print the result with a single space between head and arguments and no other spaces: integers in decimal
(`-3`, never `-0` or leading zeros), variables by name, forms as `(+ A B)`, `(- A B)`, `(* A B)`,
`(neg A)` and `(^ A N)` with `N` in decimal.

## Example

Input:

    (+ x 0)
    (* (+ 1 2) y)
    (- z z)
    (* x x)
    (neg (neg a))

Output:

    x
    (* 3 y)
    0
    (^ x 2)
    a
