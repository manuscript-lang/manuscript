# Log analyzer

Standard input is a web-server log, one record per line. A *valid* line has exactly six fields separated by
single space characters (split the line on `" "`; consecutive, leading or trailing spaces therefore create
empty fields and make the line invalid):

    TIMESTAMP LEVEL METHOD PATH STATUS LATENCY

- `TIMESTAMP`: any non-empty text.
- `LEVEL`: exactly one of `DEBUG`, `INFO`, `WARN`, `ERROR` (uppercase).
- `METHOD`: exactly one of `GET`, `POST`, `PUT`, `DELETE`.
- `PATH`: non-empty, starts with `/`.
- `STATUS`: exactly three ASCII digits.
- `LATENCY`: one or more ASCII digits (milliseconds, at most 9 digits).

Lines that are empty or contain only whitespace are skipped entirely. Every other line that is not valid
is *malformed*.

Print this report:

    valid: <number of valid lines>
    malformed: <number of malformed lines>
    DEBUG: <count>
    INFO: <count>
    WARN: <count>
    ERROR: <count>
    5xx: <valid lines whose STATUS is 500 or higher>
    top:
    <PATH> <count> avg=<avg latency>

The four level lines are always printed, in that order, even when the count is 0. After `top:` print the
three most requested paths among valid lines (fewer if there are fewer distinct paths), one per line, ordered
by request count descending and then by path ascending (byte order). `avg` is the total latency of that
path's requests divided by its request count, rounded down to an integer. If there are no valid lines,
`top:` is followed by nothing.

Example input:

    2024-05-01T10:00:00 INFO GET /api/users 200 12
    2024-05-01T10:00:01 ERROR POST /api/orders 503 250
    this line is broken
    2024-05-01T10:00:02 INFO GET /api/users 200 15
    2024-05-01T10:00:03 WARN GET /health 404 1

Output:

    valid: 4
    malformed: 1
    DEBUG: 0
    INFO: 2
    WARN: 1
    ERROR: 1
    5xx: 1
    top:
    /api/users 2 avg=13
    /api/orders 1 avg=250
    /health 1 avg=1
