# Run-length codec

Each non-blank input line is a command: a command letter, one space, then the payload. A line that is
empty or only spaces produces no output. Every other line produces exactly one output line.

- `E <text>` encodes. The payload must be non-empty and contain only ASCII letters (`A-Z`, `a-z`). Output
  one `<count><letter>` pair for every maximal run of the same letter, in order, with the count in
  decimal. Letters are case-sensitive, so `aA` is two runs.
- `D <text>` decodes. The payload must be one or more `<count><letter>` pairs, where `count` is a decimal
  number with no leading zero (so at least 1) and `letter` is an ASCII letter. Output each letter repeated
  `count` times, concatenated in order. Adjacent pairs may use the same letter (`2a3a` decodes to `aaaaa`).
  Tests use counts of at most 99999.

Anything else prints `error`: a payload that breaks the rules above, an unknown command letter
(command letters are case-sensitive), or a line with no space (such as `E` alone).

Example input:

    E aaabccdddd
    D 3a1b2c
    E ab1
    D 0a
    X hello
    D 2a3a

Output:

    3a1b2c1d
    aaabcc
    error
    error
    error
    aaaaa
