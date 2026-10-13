# Validation pipeline

The input has two parts: a *pipeline definition* (a list of steps), a separator line `---`, and a list of
*records*. Run every record through the steps in order. Steps may transform the record or validate it; for
each record report the **first failing step**, or the cleaned-up record if every step passes.

Lines are separated by `\n`. Tokens inside step lines are separated by runs of spaces and tabs. A blank line
(only spaces and tabs) is ignored in both parts. The separator is the first line that is exactly `---`
once spaces and tabs are removed from both ends; if there is no separator line, all lines are steps and there
are no records. Any later `---` line is just a record line.

## Pipeline definition

One step per line (before the separator). A *field name* matches `[a-z_][a-z0-9_]*`. An *integer* is an
optional `-` followed by ASCII digits (leading zeros allowed). `MIN`/`MAX` are integers (non-negative for
`len`) with `MIN <= MAX` compared numerically. All numbers fit comfortably in signed 64-bit range. Other
arguments are single tokens (no spaces).

| step | arguments | effect |
| --- | --- | --- |
| `trim` | `F` | if `F` is present, remove leading and trailing spaces and tabs from its value |
| `lower` | `F` | if present, convert ASCII `A-Z` in the value to lowercase |
| `default` | `F VALUE` | if `F` is absent or its value is empty, set it to `VALUE` |
| `required` | `F` | fails unless `F` is present with a non-empty value |
| `int` | `F MIN MAX` | if present, the value must be an integer within `MIN..MAX` |
| `len` | `F MIN MAX` | if present, the value's length (in characters) must be within `MIN..MAX` |
| `oneof` | `F OPTIONS` | if present, the value must equal one of the `\|`-separated options (an option may be empty, e.g. `red\|green\|`) |
| `pattern` | `F MASK` | if present, the whole value must match `MASK` |
| `unique` | `F` | if present, the value must not equal a value registered by an earlier record (see below) |
| `less` | `A B` | if both fields are present, both must be integers and `A < B` numerically |
| `needs` | `F VALUE OTHER` | if `F` is present and equals `VALUE`, then `OTHER` must be present and non-empty |

A mask is matched against the entire value: `9` matches one ASCII digit, `a` matches one ASCII letter, `*`
matches any sequence of characters (including none), and every other character matches itself. Validation
steps do nothing when their field is absent (an empty value is *present*), except `required`.

If any step line is invalid, print only one line and stop (records are not processed):

- `pipeline error: line N: unknown step WORD` if the first token is not a step word above;
- `pipeline error: line N: bad arguments for WORD` if the argument count is wrong, a field name is invalid,
  a `MIN`/`MAX` is not valid for its step, or `MIN > MAX`.

`N` is the 1-based number of the line in the whole input (blank lines count). The first invalid step line
wins. Steps are numbered 1, 2, 3, ... in order among the non-blank step lines; a step's *label* is its tokens
joined with single spaces (for example `int age 0 120`).

## Records

Each non-blank line after the separator is one record and is numbered 1, 2, 3, ... in order. The line is
used exactly as written (no trimming): it is split on every `,` into pieces; each piece must be
`KEY=VALUE` where `KEY` is a valid field name and `VALUE` is everything after the first `=` (possibly empty,
possibly containing spaces or more `=`). The parse fails at the first problem, in piece order:

- a piece without `=` or with an invalid key (including an empty piece, as from `a=1,,b=2` or a trailing
  comma): `bad field 'PIECE'` quoting the piece exactly;
- a key that appeared in an earlier piece of the same record: `duplicate key KEY`.

## Running a record

Apply the steps in order, mutating the record as transforms say. At the first failing step stop and report
it. Failure messages (`F`, `A`, `B`, `OTHER`, `VALUE`, `MIN`, `MAX` are the step's arguments, with `MIN`
and `MAX` printed as integers without leading zeros or `+`):

| step | message |
| --- | --- |
| `required` | `F is required` |
| `int` | `F is not an integer` when the value is not an integer, else `F out of range MIN..MAX` |
| `len` | `F length out of range MIN..MAX` |
| `oneof` | `F not one of OPTIONS` (the options argument exactly as written) |
| `pattern` | `F does not match MASK` |
| `unique` | `F duplicates record K` (`K` is the number of the earlier record that registered the value) |
| `less` | `A is not an integer` (checked first), `B is not an integer`, or `A must be less than B` |
| `needs` | `OTHER is required when F=VALUE` |

`unique` registry: when a record passes **all** steps, then for every `unique F` step in the pipeline, if
`F` is present in the record, its **final** value (after every step, including steps listed after the
`unique` step) is registered for field `F`, mapped to this record's number (the first record to register a
value keeps it). A record that fails registers nothing. A `unique` step compares the value the record has
*at that step* with the registry.

## Output

For each record, one line:

- parse failure: `record N: FAILED parse: DETAIL`;
- failing step: `record N: FAILED step I (LABEL): MESSAGE` where `I` is the step number;
- success: `record N: ok KEY=VALUE,KEY=VALUE,...` listing the final fields sorted by key in ascending
  byte order, values exactly as stored (they may contain spaces or be empty).

After all records print the summary

    summary records=T ok=O failed=F

followed by `failed at parse: P` if `P > 0`, then, for every step with at least one failure, in step order,
`failed at step I (LABEL): K`. With no records, only the summary line is printed.

## Example

Input:

    trim name
    required name
    int age 0 120
    ---
    name= bob ,age=30
    name=,age=5
    name=al,age=200
    name=cy,age=x

Output:

    record 1: ok age=30,name=bob
    record 2: FAILED step 2 (required name): name is required
    record 3: FAILED step 3 (int age 0 120): age out of range 0..120
    record 4: FAILED step 3 (int age 0 120): age is not an integer
    summary records=4 ok=1 failed=3
    failed at step 2 (required name): 1
    failed at step 3 (int age 0 120): 2
