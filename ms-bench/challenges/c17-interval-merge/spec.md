# Interval merge

The first line is the *mode*. Every following non-blank line (blank means empty or only spaces) is a closed
integer interval `A B`: two integers separated by one space, with `A <= B`. An integer is an optional
leading `-` followed by 1 to 10 ASCII digits (no `+`, no spaces; leading zeros and `-0` are allowed and
mean the usual value). The interval contains every integer from `A` to `B` inclusive.

Modes:

- `merge`: print the union of all intervals as the fewest disjoint intervals, in ascending order, one
  `A B` per line. Intervals that overlap **or are adjacent** (`1 3` and `4 6`) are combined (`1 6`),
  because their integers form one unbroken run. Print nothing if there are no intervals.
- `total`: print the number of distinct integers covered by the union (`0` if there are no intervals).
- `gaps LO HI`: print the maximal runs of integers in `LO..HI` that are covered by **no** interval, in
  ascending order, one `A B` per line (a single missing integer `7` is `7 7`). If everything in `LO..HI` is
  covered, print `none`. `LO` and `HI` are integers in the format above with `LO <= HI`.

Errors:

- If the first line is not a valid mode (including `gaps` with a missing, extra or malformed `LO HI`, or
  `LO > HI`, or an empty line), print `error: bad mode` and nothing else.
- Otherwise, if any interval line is malformed (wrong number of tokens, bad integer, or `A > B`), print
  `error: line N` where N is the 1-based physical line number of the first such line (the mode line is line
  1, blank lines count) and nothing else.

Numbers are printed canonically (`007` as `7`, `-0` as `0`).

Example input:

    merge
    8 10
    1 3
    2 6
    15 18
    17 20

Output:

    1 6
    8 10
    15 20
