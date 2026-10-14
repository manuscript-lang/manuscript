# Cron next runs

For each non-blank input line (blank means empty or only spaces), compute the next run times of a cron
schedule. A line has exactly 7 tokens separated by single spaces:

    START COUNT MINUTE HOUR DAY-OF-MONTH MONTH DAY-OF-WEEK

For example `2024-02-28T23:59 3 */15 9-17 * * 1-5`.

## Fields

- `START` is `YYYY-MM-DDTHH:MM` (a literal `T`), a real calendar date and time with year 1970 to 2099
  (Gregorian leap years: divisible by 4, except centuries not divisible by 400), hour 00 to 23, minute
  00 to 59. All digits are ASCII and the lengths are exactly 4-2-2, 2, 2.
- `COUNT` is 1 or 2 ASCII digits with a value from 1 to 20.
- The five cron fields use these ranges: minute `0-59`, hour `0-23`, day-of-month `1-31`, month `1-12`,
  day-of-week `0-6` where `0` is Sunday. A field is a comma-separated list of one or more items; each
  item is one of:
  - `*`: every value in the field's range;
  - `*/S`: every `S`-th value starting at the range minimum;
  - `A`: a single number;
  - `A-B` (with `A <= B`): the numbers `A` through `B`;
  - `A-B/S`: every `S`-th number from `A` to `B`, starting at `A`.
  Numbers and steps are 1 to 2 ASCII digits (no sign); every number must be inside the field's range and a
  step `S` must be at least 1. Empty items, spaces, and any other syntax are invalid.

## Matching

A minute matches when its minute, hour, month, day-of-month **and** day-of-week all match their fields
(this is a plain AND; there is no special "either" rule for day fields). A day-of-month that a month does not
have (such as 31 in April, or 30 in February) simply never matches. 1970-01-01 was a Thursday.

The result is the first `COUNT` matching minutes that are **strictly after** `START`, in increasing order.
Only calendar days from the date of `START` up to and including the day 3000 days later are searched; if
fewer than `COUNT` matches exist in that window, only those found are returned.

## Output

For each line, one header line followed by the run lines:

- `line <N>: <k> runs` where `N` is the 1-based physical line number (blank lines count) and `k` is the number
  of runs found (1 or more), followed by `k` lines `YYYY-MM-DD HH:MM`;
- `line <N>: never` if no match was found in the window (no further lines);
- `line <N>: error: <message>` for an invalid line (no further lines). Checks in this order:
  token count not 7: `bad line`; `START` invalid: `bad start`; `COUNT` invalid: `bad count`; then the
  fields in the order minute, hour, day-of-month, month, day-of-week, the first invalid one giving
  `bad minute`, `bad hour`, `bad day-of-month`, `bad month` or `bad day-of-week`.

Example input:

    2024-02-28T23:59 3 0 0 * * *
    2024-01-31T12:00 2 30 8 29 2 *
    2024-03-01T00:00 2 0 12 * * 1-5/2

Output:

    line 1: 3 runs
    2024-02-29 00:00
    2024-03-01 00:00
    2024-03-02 00:00
    line 2: 2 runs
    2024-02-29 08:30
    2028-02-29 08:30
    line 3: 2 runs
    2024-03-01 12:00
    2024-03-04 12:00
