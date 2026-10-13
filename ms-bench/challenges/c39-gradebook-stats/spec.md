# Gradebook statistics

Build a weighted gradebook and print a ranked report. Each non-blank input line is a command; tokens are separated
by runs of spaces or tabs. Names are tokens without whitespace. Blank lines produce no output. Each command prints
exactly one line, except `report`.

| command | meaning |
| --- | --- |
| `assign A MAX W` | define assignment `A` worth `MAX` points with integer weight `W` |
| `student S` | register student `S` |
| `score S A POINTS` | record `S`'s points on `A` |
| `report` | print the ranked report |

`MAX`, `W` and `POINTS` are non-empty strings of ASCII digits; `MAX` and `W` must be greater than 0, and `POINTS` must
satisfy `0 <= POINTS <= MAX` of the assignment. A wrong token count or an unknown command word prints
`error: bad command`.

## Commands

- `assign`: `error: bad number` for an invalid `MAX` or `W` (checked as one rule), then
  `error: assignment exists A`; success prints `ok`.
- `student`: `error: student exists S` or `ok`.
- `score`, in order: `error: unknown student S`, `error: unknown assignment A`, `error: bad points`; success prints
  `ok`. A later score for the same student and assignment replaces the earlier one.

## Arithmetic (integers only)

Every percentage is kept in *tenths of a percent* and rounded half up with integer arithmetic.

- Assignment score of a student: `t = (2000 * POINTS + MAX) / (2 * MAX)` (integer division). A missing score counts as
  `POINTS = 0`.
- Final grade of a student: `S = sum(W_i * t_i)` over **all** defined assignments and `T = sum(W_i)`;
  `F = (2 * S + T) / (2 * T)` (integer division). If `T = 0` (no assignments) then `F = 0`.
- Letter: `A` if `F >= 900`, `B` if `F >= 800`, `C` if `F >= 700`, `D` if `F >= 600`, otherwise `F`.
- A tenths value `v` is printed as `v / 10`, a dot, and `v % 10` (e.g. `875` is `87.5`, `5` is `0.5`).

## Report

If there are no students print `no students`. Otherwise print:

1. One line per student `RANK NAME PCT LETTER`, ordered by `F` descending then name ascending (byte-wise). `RANK` is
   the competition rank: 1 plus the number of students with a strictly higher `F` (so ties share a rank and the next
   rank is skipped).
2. `class: n=N min=MIN max=MAX mean=MEAN median=MEDIAN` over the finals. `MEAN = (2 * sum + N) / (2 * N)`. `MEDIAN` is
   the middle final of the ascending list when `N` is odd, and `(a + b + 1) / 2` of the two middle finals `a`, `b`
   when `N` is even.
3. `grades: A=a B=b C=c D=d F=f` (number of students per letter).
4. One line `assignment NAME mean=X` for each assignment in ascending name order, where `X` is
   `(2 * sum_t + N) / (2 * N)` of the students' assignment scores `t` (missing counted as 0).

## Example

Input:

    assign hw1 20 30
    assign exam 50 70
    student ann
    student bob
    student cy
    score ann hw1 20
    score ann exam 41
    score bob hw1 10
    score bob exam 46
    report

Output:

    ok
    ok
    ok
    ok
    ok
    ok
    ok
    ok
    ok
    1 ann 87.4 B
    2 bob 79.4 C
    3 cy 0.0 F
    class: n=3 min=0.0 max=87.4 mean=55.6 median=79.4
    grades: A=0 B=1 C=1 D=0 F=1
    assignment exam mean=58.0
    assignment hw1 mean=50.0
