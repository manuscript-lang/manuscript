# Payroll from timesheets

Compute weekly pay with overtime from a timesheet export. All money is integer cents; "round half up"
means a value exactly halfway rounds up.

## Input

Lines are processed in order. Blank lines (empty or only spaces) are ignored. Line numbers below are 1-based
physical line numbers (blank lines count). The input has two sections, each introduced by a header line
that must match exactly:

    [rates]
    ann=2500
    bob=1800
    [shifts]
    ann,2024-03-04,09:00,17:30,30

- Any other line starting with `[` is an unknown section: it is rejected with reason `unknown section`
  and the lines that follow it belong to no section. A non-blank line that is not a section header and
  appears while no section is active (before the first header, or after an unknown section) is rejected
  with reason `outside section`.
- `[rates]` lines are `name=cents`: `name` is one or more lowercase ASCII letters and `cents` is the hourly
  rate in cents, 1 to 6 ASCII digits with a value from 1 to 100000. A line that does not fit is rejected
  as `bad rate`; a name that already has a rate is rejected as `duplicate employee`.
- `[shifts]` lines are CSV with exactly 5 fields (no quoting) `employee,date,start,end,break_min`; another
  field count is rejected as `malformed row`. Otherwise the checks are, in this order:
  1. `employee` has a rate: else `unknown employee` (the rate must have been defined earlier in the input)
  2. `date` is `YYYY-MM-DD`, a real date with year 1970 to 2099: else `bad date`
  3. `start` and `end` are `HH:MM` with hour 00 to 23 and minute 00 to 59 (exactly two digits each): else
     `bad time`
  4. `end` is later than `start` (shifts do not cross midnight): else `end not after start`
  5. `break_min` is 1 to 3 ASCII digits: else `bad break`
  6. `break_min` is less than the shift length in minutes: else `break too long`
  7. the shift does not overlap an already accepted shift of the same employee on the same date; shifts
     overlap when `start1 < end2` and `start2 < end1` (touching shifts are fine): else `overlapping shift`

A shift is worth `end - start - break_min` minutes.

## Pay

Weeks run Monday to Sunday (1970-01-01 was a Thursday). For one employee and one week with `M` worked
minutes in total: `regular = min(M, 2400)` and `overtime = M - regular`. With hourly rate `r`:
`regular_pay = round_half_up(regular * r / 60)` and `overtime_pay = round_half_up(overtime * r * 3 / 120)`
(time and a half). Pay is computed per week and then summed over the employee's weeks.

## Output

1. One line per rejected line, in input order: `line <N>: rejected: <reason>`
2. One line per employee with at least one accepted shift, in byte order of the name:
   `<name> | weeks=<number of distinct weeks with shifts> | worked=<H>:<MM> | regular=<money> | overtime=<money> | total=<money>`
   where `worked` is the total minutes as hours and two-digit minutes (`41:05`) and `regular` / `overtime`
   are the summed pay amounts.
3. Always last: `payroll employees=<count of lines in step 2> shifts=<accepted shifts> rejected=<count> total=<money>`

Money is dollars with two decimals (`1234.05`).

Example input:

    [rates]
    ann=2500
    bob=1800
    [shifts]
    ann,2024-03-04,09:00,17:30,30
    ann,2024-03-05,08:00,18:00,0
    bob,2024-03-04,09:00,12:00,0
    bob,2024-03-04,11:00,13:00,0
    cy,2024-03-04,09:00,10:00,0

Output:

    line 8: rejected: overlapping shift
    line 9: rejected: unknown employee
    ann | weeks=1 | worked=18:00 | regular=450.00 | overtime=0.00 | total=450.00
    bob | weeks=1 | worked=3:00 | regular=54.00 | overtime=0.00 | total=54.00
    payroll employees=2 shifts=3 rejected=2 total=504.00
