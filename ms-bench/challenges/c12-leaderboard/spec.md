# Leaderboard sorting

The first input line is the *mode*: `rank`, `dense` or `stable`. Any other first line (including an empty
one) prints the single line `error: bad mode` and nothing else.

Every following line is a record `<name> <score>`: exactly two tokens separated by one space. `name` is
non-empty and has no spaces; `score` is a decimal integer with an optional leading `-` and 1 to 9 digits
(`-0` and leading zeros are allowed and mean the usual value). Blank lines (empty or only spaces) are
ignored. Any other line is *invalid*; it is skipped and counted. The same name may appear several times;
every valid line is a separate entry.

Sort the valid entries by score, highest first, then print one line per entry:

- `rank`: ties are broken by name ascending in byte order (entries with equal name and score are
  interchangeable). Print `<rank> <name> <score>` using *competition ranking*: entries with equal score
  share a rank, and the next lower score gets the rank equal to its 1-based position (so scores
  `90 80 80 70` get ranks `1 2 2 4`).
- `dense`: same order and format as `rank`, but *dense ranking*: ranks are consecutive (`90 80 80 70` get
  `1 2 2 3`).
- `stable`: entries with equal score keep their input order. Print `<name> <score>` with no rank.

Scores are printed as integers in canonical form (`007` prints `7`, `-0` prints `0`). If there was at
least one invalid line, finish with the line `skipped: <count>`. With no valid entries, only that line (if
any) is printed.

Example input:

    rank
    ann 90
    bob 80
    cat 80
    dan 70
    eve
    fay x1

Output:

    1 ann 90
    2 bob 80
    2 cat 80
    4 dan 70
    skipped: 2
