# Unified diff

Compare two texts line by line and print a unified diff with a configurable amount of context.

## Input

The first line is a header `NAME_A NAME_B CONTEXT N M`, five tokens separated by single spaces:
`NAME_A` and `NAME_B` are names without whitespace, `CONTEXT` is a non-negative integer (the number of
context lines), and `N` and `M` are the line counts of the two texts (possibly 0). The next `N` lines are the
lines of text A, and the following `M` lines are the lines of text B. A line may be empty, may have leading or
trailing spaces, and may contain any printable ASCII; it is taken exactly as it appears, without its line
terminator. Nothing follows the last line of B.

## The edit script

Number the lines of A as `a[0..N)` and of B as `b[0..M)`. Let `L(i, j)` be the length of the longest common
subsequence of `a[i..]` and `b[j..]`. The edit script is produced by walking from `(i, j) = (0, 0)`:

1. if `i = N` and `j = M`, stop;
2. if `i < N`, `j < M` and `a[i] = b[j]`: emit an unchanged line `a[i]` and advance both;
3. otherwise, if `j = M`, or (`i < N` and `L(i+1, j) >= L(i, j+1)`): emit a deletion of `a[i]` and advance `i`;
4. otherwise emit an insertion of `b[j]` and advance `j`.

This rule fully determines the script, including which of several equally long common subsequences is used
(deletions are preferred over insertions when both are possible, and equal lines are matched as early as
possible).

## Hunks

A *change* is a deletion or insertion in the script. If the script has no changes, print nothing at all.
Otherwise print the header lines

    --- NAME_A
    +++ NAME_B

followed by hunks. Consecutive changes belong to the same hunk when the number of unchanged lines between them
is at most `2 * CONTEXT`; a longer run of unchanged lines separates hunks. A hunk consists of its changes, all
the unchanged lines between them, and up to `CONTEXT` unchanged lines immediately before its first change and
immediately after its last change (fewer if the script starts or ends sooner). Hunks never overlap or touch.

Each hunk starts with `@@ -SA[,LA] +SB[,LB] @@` and then lists its script lines in order: unchanged lines
prefixed with a space, deletions with `-`, insertions with `+`, each followed by the line text.

- `LA` is the number of unchanged plus deleted lines in the hunk; `LB` the number of unchanged plus inserted
  lines.
- `SA` is the number of lines of A that come before the hunk in the script, plus 1 when `LA > 0` (so for a
  hunk with `LA = 0` it is the 1-based number of the line just before it, or 0 at the start of the file).
  `SB` is defined the same way for B.
- `,L` is omitted when the length is exactly 1 (`@@ -5 +5,2 @@`); a length of 0 prints `,0`.

## Example

Input:

    old.txt new.txt 1 6 6
    one
    two
    three
    four
    five
    six
    one
    two
    3
    four
    five
    seven

Output:

    --- old.txt
    +++ new.txt
    @@ -2,5 +2,5 @@
     two
    -three
    +3
     four
     five
    -six
    +seven

(Here the two changes are separated by two unchanged lines, which is at most `2 * CONTEXT`, so they share one
hunk.)
