# Number theory commands

Each non-blank input line (blank means empty or only spaces) is a command and produces one output line.
A line is split on single spaces into tokens (`gcd  4 6`, with two spaces, has an empty token). The first
token is the command name (case-sensitive).

Commands (a *number* is 1 to 18 ASCII decimal digits, leading zeros allowed, no sign):

- `gcd A B`: greatest common divisor of two numbers. `gcd 0 0` is `0`, and `gcd 0 x` is `x`.
- `lcm A B`: least common multiple; `0` if either number is `0`.
- `isprime N`: `prime` if N is prime, `composite` if N >= 2 and not prime, `neither` if N is 0 or 1.
- `factor N`: prime factorization of N >= 2 as factors in increasing order joined by ` * `, where a prime
  p appearing e times is written `p^e` if e > 1 and `p` if e = 1. Examples: `360` gives `2^3 * 3^2 * 5`,
  a prime `97` gives `97`. For N < 2 print `error: n must be at least 2`.
- `base V FROM TO`: convert V, a non-negative integer written in base FROM, to base TO. FROM and TO are
  decimal integers from 2 to 36 (written as numbers; anything else, or outside the range, is
  `error: bad base`). V uses digits `0-9` and letters `a-z` or `A-Z` (letters are 10 to 35, either case);
  V must be non-empty and every digit must be smaller than FROM, otherwise `error: bad digit`. Output uses
  lowercase letters, no leading zeros (`0` for zero). Tests keep the value of V below 10^18.

Errors, checked in this order; the first failure decides the output:

1. Unknown command name: `error: unknown command`
2. Wrong number of tokens (`gcd` and `lcm` take 3 tokens in total, `isprime` and `factor` take 2, `base`
   takes 4), or, for the four numeric commands, an argument that is not a *number*:
   `error: bad arguments`
3. `gcd`/`lcm` with an argument above 10^9, or `isprime`/`factor` with an argument above 10^10:
   `error: out of range`

For `base` only the token count is checked in step 2 (the value V is not a *number*); then FROM and TO are
validated (`error: bad base`), then V (`error: bad digit`).

Example input:

    gcd 12 18
    lcm 4 6
    isprime 97
    factor 360
    base ff 16 2
    base 12 2 10
    factor 1
    pow 2 3
    gcd 4

Output:

    6
    12
    prime
    2^3 * 3^2 * 5
    11111111
    error: bad digit
    error: n must be at least 2
    error: unknown command
    error: bad arguments
