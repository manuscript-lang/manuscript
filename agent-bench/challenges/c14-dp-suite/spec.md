# Dynamic programming suite

Each non-blank input line (blank means empty or only spaces) is a command and produces exactly one output
line. A line is split on single spaces into tokens; the first token is the command name (case-sensitive).

- `lcs A B`: length of the longest common subsequence of `A` and `B`.
- `edit A B`: Levenshtein edit distance between `A` and `B` (minimum number of single-character
  insertions, deletions and substitutions that turn `A` into `B`).
- `knap CAP w:v w:v ...`: 0/1 knapsack. `CAP` is the capacity; each following token is an item with weight
  `w` and value `v`. Each item can be used at most once. Output the maximum total value of a set of items
  whose total weight is at most `CAP`. Zero items is allowed (the answer is `0`).
- `coins AMOUNT c1 c2 ...`: the minimum number of coins (each denomination may be used any number of
  times) whose values sum to exactly `AMOUNT`, or `impossible` if no combination works. `AMOUNT` of `0`
  needs `0` coins. At least one denomination is required.

`A` and `B` are non-empty tokens of any characters except a space; comparison is by bytes (tests use
ASCII only). All numbers (`CAP`, `w`, `v`, `AMOUNT`, `c`) are decimal with 1 to 6 digits, no sign;
weights `w` and coin values `c` must be at least 1 (values `v` and `CAP` and `AMOUNT` may be 0).

Anything that does not fit the command forms above (unknown command, wrong token count, a malformed
number or item, `w` or `c` equal to 0) prints `error: bad command`.

Example input:

    lcs AGGTAB GXTXAYB
    edit kitten sitting
    knap 10 5:10 4:40 6:30 3:50
    coins 11 1 2 5
    coins 3 2
    edit a
    knap 5 0:3

Output:

    4
    3
    90
    3
    impossible
    error: bad command
    error: bad command
