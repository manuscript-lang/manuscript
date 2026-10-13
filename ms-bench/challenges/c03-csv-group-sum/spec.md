# CSV group sum

Each input line is a record `category,amount`.

- `category` is non-empty text. It may be wrapped in double quotes, in which case it may contain
  commas; the quotes are not part of the category. There are no escaped quotes inside quoted fields.
- `amount` is a non-negative decimal: digits, optionally followed by `.` and one or two digits
  (`5`, `12.5`, `0.07`). No sign, no spaces.

A line is *invalid* if it does not split into exactly two fields under the rules above, if the
category is empty, or if the amount does not match. Blank lines are ignored (not invalid).

Output, one line per distinct category in byte order: `<category>: <total>`, where total is the sum
of that category's amounts with exactly two decimals. Sums are exact decimal sums (do not use floats).
If there is at least one invalid line, finish with `skipped: <count>`.

Example input:

    fruit,1.50
    "a,b",2
    fruit,0.5
    oops
    veg,x

Output:

    a,b: 2.00
    fruit: 2.00
    skipped: 2
