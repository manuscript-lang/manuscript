# Regex engine

Implement a backtracking regular-expression engine from scratch (no regex library) and a small command driver.
Standard input is a list of commands, one per line. Each command prints its result to standard output. The exit
status is always 0.

## Input

A line is a command with fields separated by a single TAB character (the pattern, subject and replacement never
contain a raw TAB; use escapes). Empty lines are ignored.

| command | fields |
| --- | --- |
| `test` | `test<TAB>pattern<TAB>subject` |
| `match` | `match<TAB>pattern<TAB>subject` |
| `full` | `full<TAB>pattern<TAB>subject` |
| `find-all` | `find-all<TAB>pattern<TAB>subject` |
| `split` | `split<TAB>pattern<TAB>subject` |
| `replace` | `replace<TAB>pattern<TAB>subject<TAB>replacement` |

The line is split at every TAB. If the command name is unknown (names are case-sensitive) or the number of fields
is not exactly 3 (4 for `replace`), print `error: bad command`. The *subject* and the *replacement* fields are then
unescaped: `\n` newline, `\t` TAB, `\\` backslash, `\xHH` (two hex digits, either case) the byte with that value; any
other backslash sequence, a trailing lone backslash, or a bad `\x` is `error: bad command`. The pattern is **not**
unescaped (it has its own escapes, below). Order of checks: command/field count, subject unescape, replacement
unescape, pattern compilation (pattern errors), execution (replacement errors).

Strings are byte strings (bytes 0-255; positions are byte offsets).

## Pattern syntax

Matching is Perl-style: leftmost match, and among matches starting at the same position the one found first by
backtracking with the priorities below.

Atoms:

- Any byte other than the specials is a literal. Specials: `\ . ^ $ | ? * + ( ) [`. The characters `]`, `}` and `{`
  are literals except that `{...}` forms a quantifier when it follows an atom (below). A `{` at the start of a
  pattern, group or alternative is always a literal.
- `.` matches any byte except `\n` (any byte at all with the `s` flag).
- `[...]` character class. `[^...]` negated. A `]` immediately after `[` or `[^` is a literal member. Members:
  single bytes, ranges `a-z`, shorthand classes `\d \D \w \W \s \S` and escapes (`\n \t \r \xHH`, or `\` plus any
  non-alphanumeric ASCII character meaning that character). A `-` that is first, last, or directly after a range is
  literal. A range whose end is below its start (`[z-a]`), or a range with a shorthand class as an endpoint
  (`[\d-z]`, `[a-\d]`), is `bad range` (but `[\d-]` and `[-\d]` are fine). Any other alphanumeric escape inside a class
  (including `\b`, `\1`, `\k`) is `bad escape`. A missing `]` is `unterminated class`.
- Escapes outside classes: `\d` digits `0-9`; `\w` `[A-Za-z0-9_]`; `\s` space, `\t`, `\n`, `\r`, `\f`, `\v`; `\D \W \S`
  their complements; `\n` `\t` `\r` the control characters; `\xHH` a byte; `\b` word boundary, `\B` not a word
  boundary (a boundary is a position where exactly one of the neighbouring bytes, treating outside the subject as non-word,
  is a word byte); `\1` to `\9` backreference; `\k<name>` named backreference; `\` plus any non-alphanumeric ASCII
  character is that character. Every other escape (`\q`, `\0`, `\A`, `\z`, `\p`, `\u`, a bad `\x`, `\k` without
  `<name>`, a trailing `\`) is `bad escape`.
- `^` start of the subject (with `m`: also after any `\n`). `$` end of the subject (with `m`: also before any `\n`);
  without `m`, `$` does **not** match before a final `\n`.
- `(...)` capturing group, numbered 1, 2, ... by the position of its opening parenthesis. `(?:...)` non-capturing.
  `(?<name>...)` named capturing group (name `[A-Za-z_][A-Za-z0-9_]*`, a name already used is `duplicate group name`).
  `(?=...)` positive and `(?!...)` negative lookahead. Any other `(?...)` (including `(?<=`, `(?<!`, `(?>`, `(?i:`,
  a malformed name) is `bad group`.
- Flags: a pattern may begin with `(?` followed by one or more of `i`, `m`, `s` and `)`. `i`: ASCII case-insensitive
  (literals, classes, backreferences), `m`: multiline anchors, `s`: dot matches `\n`. `(?i)` anywhere else is
  `bad group`.
- Alternation `a|b|c` (lowest precedence; alternatives may be empty). Alternatives are tried left to right.

Quantifiers apply to the preceding atom: `*` `+` `?` `{n}` `{n,}` `{n,m}` (decimal digits only). A `{` that does not
form one of these three shapes is a literal `{`. Greedy by default; a trailing `?` makes it lazy. If `n > m`, or
`n` or `m` is greater than 1000 (any number of digits), the error is `bad repeat`. Quantifying an anchor, `\b`,
`\B` or a lookahead, or a quantifier directly after a quantifier (including after its lazy `?`, e.g. `a**`, `a+?+`,
`a{2}{3}`, `a???`) or at the start of a pattern/group/alternative, is `nothing to repeat`.

Unmatched parentheses: a `(` with no `)` is `unmatched (`; a stray `)` is `unmatched )`.

Backreferences: `\N` must satisfy `N <=` the total number of capturing groups in the whole pattern and `\k<name>`
must name an existing group, else `bad backreference`; this check happens **after** the whole pattern has parsed (all
other pattern errors are reported in left-to-right order of the first problem found). A backreference to a group that
has not captured in the current attempt (including a group still open) fails to match. Otherwise it matches the same
bytes the group captured (case-insensitively with `i`).

Errors print as `error: MESSAGE` for the exact messages in this document.

## Matching semantics

- A pattern is tried at start positions 0, 1, ..., length, and the first start position that has a match wins.
  Within a start position, standard backtracking with these priorities: alternation left to right; greedy
  quantifiers try more iterations first, lazy ones fewer; the sequence backtracks into earlier items.
- A repeat is `{min,max}` (max may be unbounded). Iterations up to `min` are mandatory. Once `min` is reached, an
  iteration that consumes no bytes is not followed by another iteration: the loop ends and the match continues after the
  loop (with that iteration's captures kept). Greedy: try one more iteration (and if it succeeds the rest), else
  continue without it; lazy: try continuing first, then one more iteration.
- Captures: a group records its span when its body completes; spans from earlier iterations persist if a later
  iteration does not set them (they are not reset), and captures are undone when backtracking past the group. A group
  that did not participate is *unset*.
- Lookahead bodies are matched atomically (the first successful way only; no backtracking into them). Captures made
  inside a positive lookahead stay set; captures inside a negative lookahead are discarded.
- `full` requires the match to start at 0 and end at the end of the subject; among the ways to match, the first by the
  priorities above that ends at the end (not the longest).

## Commands and output

Quoting: *quoted(s)* is `"` + s with `\` as `\\`, `"` as `\"`, newline as `\n`, TAB as `\t`, carriage return as `\r`,
any other byte below 0x20 or above 0x7e as `\xHH` (two lowercase hex digits) + `"`.

- `test`: print `true` if the pattern matches anywhere, else `false`.
- `match`: leftmost match; if none print `no match`. Otherwise print one line per group from 0 (the whole match) to the
  last: `G: S..E quoted` for a group that captured (S and E are byte offsets, end exclusive), `G: unset` otherwise; for a
  named group the label is `G (name)` instead of `G`.
- `full`: same output as `match`, for the anchored whole-subject match.
- `find-all`: the list of successive matches, one line each `S..E quoted`, then `(N matches)`. After a match ending at
  E, the next search starts at E if the match was non-empty, or at E+1 if it was empty. Empty matches are reported
  (an empty match directly after a non-empty one is allowed): `a*` on `baac` gives `0..0`, `1..3 "aa"`, `3..3`, `4..4`.
  Searching continues while the start position is at most the subject length.
- `replace`: replace every match from the `find-all` sequence by the expansion of the replacement, print the resulting
  string as *quoted*. Expansion: `$0`-`$9` the text of that group (empty if unset; a group number above the number of
  groups is `error: bad replacement`); `$$` a literal `$`; `${name}` the named group (unknown name or missing `}` is
  `error: bad replacement`); a `$` followed by anything else, or at the end, is a literal `$`. Only a single digit
  follows `$` (`$10` is group 1 followed by `0`). If there are no matches the replacement is never expanded (so it cannot
  cause an error).
- `split`: use the `find-all` matches but ignore the empty ones. Pieces are the subject text between the kept matches
  (captures are not included): print each piece as *quoted* on its own line, then `(N pieces)`. With no non-empty
  match the single piece is the whole subject.

Pattern errors are printed instead of the normal output for that command. The exit status is 0 for all of them.

## Example

Input (TABs shown as `<TAB>`):

    match<TAB>(\d+)-(?<b>\d+)<TAB>tel 12-345
    find-all<TAB>a*<TAB>baac
    replace<TAB>(\w+)@(\w+)<TAB>me@host<TAB>$2:$1
    test<TAB>(a<TAB>a

Output:

    0: 4..10 "12-345"
    1: 4..6 "12"
    2 (b): 7..10 "345"
    0..0 ""
    1..3 "aa"
    3..3 ""
    4..4 ""
    (4 matches)
    "host:me"
    error: unmatched (
