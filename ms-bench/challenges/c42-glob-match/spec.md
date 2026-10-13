# Glob matcher

Implement shell-style path globbing. Each non-blank input line holds a *pattern* and a *path* separated by
runs of spaces or tabs, and produces exactly one output line. Neither may contain whitespace. Blank lines
produce no output.

Output, in order of precedence:

- a line with a token count other than 2: `error: bad line`
- a malformed pattern (see below): `error: invalid pattern`
- otherwise `match` or `no match`

Everything is ASCII and byte-oriented.

## Pattern syntax

| syntax | meaning |
| --- | --- |
| any other byte | matches itself |
| `?` | exactly one byte other than `/` |
| `*` | zero or more bytes other than `/` |
| `**` as a whole segment | zero or more whole path segments (see globstar) |
| `[set]`, `[!set]` | one byte in (or, with `!`, not in) the set; never matches `/` |
| `{a,b,c}` | alternation; the pattern matches if any alternative's expansion does |
| `\x` | the byte `x` literally (including `\*`, `\?`, `\[`, `\{`, `\,`, `\}`, `\\`, `\/`, `\-`, `\]`, `\!`) |

A trailing lone `\` is invalid.

**Classes.** After `[` and an optional `!`, a class lists items until the closing `]`. An item is one byte `c`
(a `\` escapes the next byte and the escaped byte is used literally), or a range `c-d` when `-` follows `c` and
is itself followed by something other than `]` (`d` may be escaped). Ranges compare byte values; `d` below `c`
is invalid. A `-` that is first, last, or otherwise not forming a range is a literal. Inside a class, `[`, `{`,
`}`, `,`, `*`, `?` and `!` are literal. A class with no items (`[]` or `[!]`) and a class with no closing `]`
are invalid.

**Braces.** `{` opens a brace group that ends at the next `}` outside any class; its alternatives are separated
by `,` (an alternative may be empty, so `{a,}` and `{}` are valid). A `{` inside a group, a `{` with no
matching `}`, and a stray unescaped `}` outside any group are invalid. A `,` outside a group is a literal.
Groups may not nest but may appear several times; the pattern expands to the cartesian product of its groups
(tests never exceed 4096 expansions). Expansion is done before anything else: the pattern matches if at least
one expansion matches. Validity is checked on the whole pattern, so an invalid pattern is reported even when
an earlier alternative would have matched.

## Matching

Split the path at every `/` into segments (so `a//b` has the empty segment between the slashes, and `a/` has
a trailing empty one; a leading `/` gives a leading empty segment). Split each expansion the same way at
every `/` it contains, whether written plainly or as `\/`. Segments must correspond one to one, except for
globstars.

**Globstar.** A pattern segment consisting of exactly two unescaped `*` and nothing else matches any number
(including zero) of consecutive path segments, each of which must not start with `.`. A `**` that is only part
of a segment (`a**`, `**b`) is two ordinary `*`.

**Dot rule.** A path segment that starts with `.` can only be matched by a pattern segment whose first element
is a literal `.` (plain or escaped). A first element of `*`, `?`, or a class never matches a leading `.`. This
includes the segments `.` and `..`. A `*` elsewhere in the segment has no such restriction.

All other elements match segments left to right as in standard globbing: `*` backtracks over any number of
bytes of the segment (including none), and the whole segment must be consumed.

## Examples

| pattern | path | result |
| --- | --- | --- |
| `src/*.ms` | `src/main.ms` | `match` |
| `src/*.ms` | `src/a/main.ms` | `no match` |
| `**/test_*.go` | `a/b/test_x.go` | `match` |
| `**/test_*.go` | `test_x.go` | `match` |
| `**/x` | `a/.hidden/x` | `no match` |
| `*.{go,rs}` | `lib.rs` | `match` |
| `[!a-c]at` | `bat` | `no match` |
| `a[` | `a` | `error: invalid pattern` |
