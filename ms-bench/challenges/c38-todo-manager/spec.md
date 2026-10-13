# Todo manager

A todo list with priorities and due dates. Each non-blank input line is a command; tokens are separated by runs
of spaces or tabs. Every command prints exactly one line, except `list`, `summary` and `agenda`. Blank lines
produce no output.

Task ids are 1, 2, 3, ... assigned in order of successful `add` commands. Priorities are the integers 1 (most
urgent), 2 and 3. A *date* is written `YYYY-MM-DD`: exactly four, two and two ASCII digits, year 1970 to 2100,
a real calendar day (Gregorian leap years). Dates compare chronologically. A task is *overdue* on date `T` when
it is open, has a due date and the due date is before `T`.

| command | meaning |
| --- | --- |
| `add P DUE TITLE...` | new task; `DUE` is a date or `-` (no due date); the title is all remaining tokens joined with single spaces (at least one token) |
| `done N` | mark open task `N` done |
| `drop N` | delete task `N` (open or done) |
| `prio N P` | change the priority |
| `snooze N DAYS` | move the due date `DAYS` days later |
| `list T` | list open tasks as of date `T` |
| `summary T` | counts as of date `T` |
| `agenda T DAYS` | open tasks due on each of the next `DAYS` days starting at `T` |

`N` and `DAYS` are non-empty strings of ASCII digits (`DAYS` may be 0 for `snooze`; for `agenda` it must be 1 to
60). A command with the wrong number of tokens (`add` needs at least 4) or an unknown command word prints
`error: bad command`.

## Mutating commands

Checks run in the listed order; the first failure wins and changes nothing.

- `add`: `error: bad priority`, `error: bad date`; success prints `added N`.
- `done`: `error: no such task N` (never created, or dropped), `error: already done N`; success prints `ok`.
- `drop`: `error: no such task N`; success prints `ok`. Ids are never reused.
- `prio`: `error: no such task N`, `error: bad priority`; success prints `ok`.
- `snooze`: `error: no such task N`, `error: bad days`, `error: already done N`, `error: no due date N`; success
  prints `ok DATE` with the new due date.

`N` is read as a decimal integer (leading zeros allowed, `007` is task 7); a token that is not all digits is "no such
task". Error messages repeat the `N` token exactly as it was written. Tests keep every date within year 9999.

## Reports

`list T`: `error: bad date` for an invalid `T`. Otherwise print the open tasks ordered by: overdue tasks first, then
priority ascending, then due date ascending with tasks that have no due date last, then id ascending. One line per
task:

    M N pP DUE TITLE

where `M` is `!` if the task is overdue and `.` otherwise, `DUE` is the date or `-`. With no open tasks print
`no open tasks`.

`summary T`: `error: bad date`, else two lines. First
`open=A done=B overdue=C today=D upcoming=E nodue=F`, where among open tasks `today` have due date equal to `T`,
`upcoming` due after `T`, `nodue` no date, and `B` counts done tasks. Second line `next: DATE xK` where `DATE` is the
earliest due date `>= T` among open tasks and `K` how many open tasks have that date, or `next: none`.

`agenda T DAYS`: `error: bad date` then `error: bad days`; otherwise `DAYS` lines, one per date `T`, `T+1`, ...,
each `DATE: ids` where ids are the open tasks due that date ordered by priority then id, joined with commas, or
`-` when there are none.

## Example

Input:

    add 2 2024-02-28 Write report
    add 1 - Call mom
    add 1 2024-03-01 Pay rent
    snooze 1 2
    done 2
    list 2024-03-01
    summary 2024-03-01
    agenda 2024-02-29 3

Output:

    added 1
    added 2
    added 3
    ok 2024-03-01
    ok
    . 3 p1 2024-03-01 Pay rent
    . 1 p2 2024-03-01 Write report
    open=2 done=1 overdue=0 today=2 upcoming=0 nodue=0
    next: 2024-03-01 x2
    2024-02-29: -
    2024-03-01: 3,1
    2024-03-02: -
