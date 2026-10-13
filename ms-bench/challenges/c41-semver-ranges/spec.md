# Semver ranges

Implement a small semantic-version range engine. Input is a script of commands, one per line; every
non-blank line produces exactly one line of output. Tokens are separated by runs of spaces or tabs, and blank
lines produce no output. The script is read until end of input.

## Versions

A *version* is `MAJOR.MINOR.PATCH` with an optional `-PRERELEASE` suffix, for example `1.2.3` or
`1.2.3-beta.2`.

- `MAJOR`, `MINOR` and `PATCH` are non-empty ASCII digit strings of at most 9 digits with no leading zeros
  (`0` itself is fine).
- `PRERELEASE` is one or more identifiers separated by `.`. An identifier is a non-empty string of ASCII
  letters, digits and `-`. An identifier made only of digits is *numeric*: it has at most 9 digits and no
  leading zeros. Anything else is *alphanumeric*. Build metadata (`+...`) is not supported and makes a version
  invalid.

Precedence: compare `MAJOR`, then `MINOR`, then `PATCH` numerically. If those are equal, a version without a
prerelease is greater than one with a prerelease. Two prereleases compare identifier by identifier from the
left: two numeric identifiers compare numerically; a numeric identifier is less than an alphanumeric one; two
alphanumeric identifiers compare by byte value; if all shared identifiers are equal the prerelease with fewer
identifiers is lower. Two versions with equal precedence are the same string.

## Ranges

A *range* is whitespace-separated tokens. The token `||` separates *sets*; a version satisfies the range if it
satisfies at least one set. A set with no tokens (for example an empty range, or the side of a `||` that has
nothing on it) is the "any" set, which has no comparators. Inside a set the tokens are *terms*, all of which
must hold.

A term is either a single token `[OP]PARTIAL`, or a hyphen range written as three tokens `PARTIAL - PARTIAL`
(the middle token is exactly `-`; neither partial may carry an operator). `OP` is one of `>=`, `<=`, `>`, `<`,
`=`, `^`, `~` (match the longest operator at the start of the token); no operator means `=`.

`PARTIAL` is `MAJOR`, `MAJOR.MINOR`, or `MAJOR.MINOR.PATCH[-PRERELEASE]`, where any component may instead be
the wildcard `x`, `X` or `*`, and the whole partial may be just a wildcard. Number and prerelease formats are as
for versions. Once a component is a wildcard, every later component must be a wildcard or absent
(`1.x.3` is invalid); a wildcard component counts as absent. A prerelease is only allowed when all three
components are numbers. Let `n` be the number of present components (0 to 3) and `M`, `m`, `p` the present
values; a missing component is 0 when a rule says "fill".

A range with any invalid term, or a lone `-` token that is not the middle of a well-formed hyphen range, or a
hyphen range missing an operand, is *invalid*. (Invalid ranges are reported as errors by the commands below,
even when another set could match.)

### Desugaring

Each term becomes a list of *comparators* `(op, version)` with `op` one of `>=`, `>`, `<`, `<=`, `==`, all of
which must hold. `fill(x)` means the partial with missing components set to 0 and the prerelease kept (if any);
`next1` is `(M+1).0.0` and `next2` is `M.(m+1).0`. The impossible comparator `<0.0.0` is called NEVER.

| term | n = 0 | n = 1 | n = 2 | n = 3 |
| --- | --- | --- | --- | --- |
| bare / `=` | none | `>=M.0.0`, `<next1` | `>=M.m.0`, `<next2` | `== full` |
| `>` | NEVER | `>=next1` | `>=next2` | `> full` |
| `>=` | none | `>= fill` | `>= fill` | `>= full` |
| `<` | NEVER | `< fill` | `< fill` | `< full` |
| `<=` | none | `<next1` | `<next2` | `<= full` |
| `~` | none | `>=M.0.0`, `<next1` | `>=M.m.0`, `<next2` | `>= full`, `<next2` |
| `^` | none | `>=M.0.0`, `<next1` | `M>0`: `>=M.m.0`, `<next1`; `M=0`: `>=0.m.0`, `<next2` | `M>0`: `>= full`, `<next1`; `M=0, m>0`: `>= full`, `<next2`; `M=0, m=0`: `>= full`, `<0.0.(p+1)` |

"none" means no comparator at all. `full` keeps the prerelease. Comparisons use version precedence.

Hyphen range `A - B`: the lower bound is `>= fill(A)` (none if `A` has `n = 0`); the upper bound is `<= B` if
`B` has `n = 3`, `<next2` if `n = 2`, `<next1` if `n = 1`, none if `n = 0`.

### Prerelease rule

A version that has a prerelease satisfies a set only if, in addition to all comparators holding, at least one
comparator of that set has the same `MAJOR.MINOR.PATCH` and itself has a prerelease. A set with no comparators
therefore never matches a prerelease version. Versions without a prerelease are not affected by this rule.

## Commands

The pool starts empty.

| command | output |
| --- | --- |
| `pool V1 V2 ...` | replace the pool with the valid versions among the arguments (invalid ones are skipped, repeats removed) and print `pool N skipped K`, where `N` is the number of distinct valid versions and `K` the number of arguments skipped as invalid. Repeats do not count as skipped. |
| `max RANGE...` | the greatest pool version satisfying the range (the range is all remaining tokens, possibly none = any), or `none` |
| `all RANGE...` | every satisfying pool version in ascending precedence order separated by single spaces, or `none` |
| `test V RANGE...` | `true` or `false`; an invalid `V` prints `invalid version` (checked first) and an invalid range `invalid range` |

For `max` and `all`, an invalid range prints `invalid range`. A line whose first token is not one of these four
commands, or a `test` with no arguments, prints `error: bad command`. Versions are printed exactly as given.

## Example

Input:

    pool 1.2.3 1.3.0 2.0.0 2.1.0-rc.1 0.9.9 bad
    max ^1.2.0
    all >=1.2.3 <2.0.0 || 0.x
    max *
    test 2.1.0-rc.1 >=2.1.0-alpha
    test 2.1.0-rc.1 >=2.0.0

Output:

    pool 5 skipped 1
    1.3.0
    0.9.9 1.2.3 1.3.0
    2.0.0
    true
    false
