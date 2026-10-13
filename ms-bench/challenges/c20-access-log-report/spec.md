# Access log report

Summarise a web server access log. Each non-blank input line (blank means empty or only spaces) should be
one request in this exact layout, with exactly one space between the parts shown:

    <ip> <ident> <user> [<timestamp>] "<method> <target> <proto>" <status> <bytes> <time>

Example line:

    203.0.113.9 - alice [10/Oct/2023:13:55:36 +0000] "GET /api/users/42?verbose=1 HTTP/1.1" 200 2326 0.123

Field rules (a line that breaks any of them is *malformed*; malformed lines are only counted):

- `ip`: four decimal numbers separated by dots, each 1 to 3 digits with value 0 to 255 (leading zeros are
  allowed).
- `ident` and `user`: non-empty, contain no space, `[` or `"` (usually `-`).
- `timestamp`: `DD/Mon/YYYY:HH:MM:SS +ZZZZ` with `DD` 01 to 31, `Mon` one of `Jan Feb Mar Apr May Jun Jul
  Aug Sep Oct Nov Dec` (exactly this capitalisation), `YYYY` four digits, `HH` 00 to 23, `MM` and `SS` 00
  to 59, and a zone made of `+` or `-` and four digits. No check that the day exists in that month.
- request: `method target proto` in double quotes. `method` is one of `GET POST PUT DELETE PATCH HEAD
  OPTIONS`; `target` starts with `/` and has no space or quote; `proto` is `HTTP/1.0`, `HTTP/1.1` or
  `HTTP/2.0`.
- `status`: three digits, 100 to 599.
- `bytes`: `-` (counts as 0) or 1 to 10 digits.
- `time`: seconds with exactly three decimals, 1 to 4 digits before the dot (`0.123`, `12.500`); its value
  in whole milliseconds is used (`0.123` is 123 ms).
- Nothing may follow `time`, and no extra spaces are allowed anywhere.

## Route of a request

Take `target`, cut it at the first `?` or `#` (whichever comes first, dropping the rest), split what is
left on `/`, replace every segment that consists only of digits (at least one) by `:id`, and join with `/`
again (`/api/users/42/orders/7?x=1` becomes `/api/users/:id/orders/:id`; `/a//b/` stays `/a//b/`).

## Report

Print exactly these lines, in this order:

1. `requests=<N> malformed=<M> bytes=<total of bytes> ips=<distinct ips>` where N counts well-formed lines
   (ip strings are compared as written).
2. `status 1xx=<a> 2xx=<b> 3xx=<c> 4xx=<d> 5xx=<e>`: counts of well-formed lines by status class.
3. `hours HH=<n> HH=<n> ...`: for each hour `00` to `23` with at least one request (hour as written in the
   timestamp, zone ignored), in ascending order, separated by single spaces; or `hours none` if N is 0.
4. If N is 0: `endpoints none`. Otherwise, up to five lines, one per distinct `<method> <route>`, taking
   the five with the highest request count (ties: the smaller `<method> <route>` text in byte order
   first), in that order:
   `endpoint <count> <method> <route> avg=<A>ms p95=<P>ms errors=<E>`
   where `A` is the mean response time in ms rounded half up to an integer, `P` is the 95th percentile by
   the *nearest-rank* method (sort the times ascending; the value at 1-based position `ceil(0.95 * count)`),
   and `E` is the number of requests with status 400 or above.

Example input:

    203.0.113.9 - alice [10/Oct/2023:13:55:36 +0000] "GET /api/users/42?verbose=1 HTTP/1.1" 200 2326 0.123
    203.0.113.9 - - [10/Oct/2023:13:56:01 +0000] "GET /api/users/7 HTTP/1.1" 404 - 0.010
    198.51.100.2 - - [10/Oct/2023:14:02:11 +0000] "POST /login HTTP/1.1" 302 0 0.250
    not a log line

Output:

    requests=3 malformed=1 bytes=2326 ips=2
    status 1xx=0 2xx=1 3xx=1 4xx=1 5xx=0
    hours 13=2 14=1
    endpoint 2 GET /api/users/:id avg=67ms p95=123ms errors=1
    endpoint 1 POST /login avg=250ms p95=250ms errors=0
