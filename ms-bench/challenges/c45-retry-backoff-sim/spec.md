# Retry and backoff simulation

Simulate clients that retry failing requests against a server with exponential backoff, deterministic jitter,
outage windows, a rate limit and a deadline. Everything is in integer milliseconds and fully deterministic.

## Input

Each non-blank line is one of the following, with tokens separated by runs of spaces or tabs. The input is
always well formed, all numbers are non-negative integers below 10^9, and IDs are unique non-empty tokens
without whitespace. Configuration lines may appear anywhere (even after `req` lines) and apply to the whole
simulation.

| line | meaning |
| --- | --- |
| `policy BASE FACTOR CAP MAX JITTER DEADLINE SEED` | retry policy; the last `policy` line wins. If there is none the defaults are `100 2 5000 5 0 0 1`. `FACTOR >= 1`, `MAX >= 1`, `0 <= JITTER <= 90` (percent), `1 <= SEED < 2147483647`. `DEADLINE` 0 means no deadline. |
| `down START END` | the server is down for times `t` with `START <= t < END`; any number of such lines, windows may overlap |
| `limit WINDOW COUNT` | rate limit: at most `COUNT` accepted requests in any sliding window of `WINDOW` ms (`WINDOW >= 1`); the last `limit` line wins; if there is none there is no limit |
| `req ID START` | a request that makes its first attempt at time `START` |

## Simulation

Each request has an attempt counter `K` (the first attempt is 1) and the time of its next attempt (initially
`START`). Repeatedly process the pending request whose next attempt time is smallest; if several requests
have the same time, the one that appeared first in the input goes first. Processing an attempt at time `t`
decides its outcome, in this order:

1. If some `down` window contains `t`: outcome `down`.
2. Otherwise, if a limit is configured and the number of previously accepted requests with acceptance time
   `a > t - WINDOW` is at least `COUNT`: outcome `limited`. The server's *retry-after* is
   `(oldest such a) + WINDOW - t` (at least 1).
3. Otherwise the attempt is accepted: outcome `ok`, `t` is recorded as an acceptance time, and the request is
   finished successfully at `t`.

On `down` or `limited`:

- If `K == MAX` the request gives up: it is finished, with status `gave-up`, and nothing else happens.
- Otherwise schedule a retry. First compute the backoff `d`: start with `d = min(CAP, BASE)`, then `K - 1`
  times replace `d` with `min(CAP, d * FACTOR)`. Then draw the next jitter value from the generator (below)
  and let `d' = max(1, d - (d * JITTER * r) / 100000)` using integer (floor) division, where `r` is the drawn
  value. The wait is `d'`, except for outcome `limited`, where it is `max(d', retry-after)`. The next attempt
  would happen at `t' = t + wait`.
- If `DEADLINE > 0` and `t' > START + DEADLINE` (the request's own start time), the request is finished with
  status `expired` and is not retried. Otherwise it becomes pending again at `t'` with `K` increased by 1.

The jitter generator is global and shared by all requests: it holds a state, initialised to `SEED`; each draw
sets `state = (state * 48271) mod 2147483647` and yields `r = state mod 1000`. A draw happens exactly when a
retry time is being computed (including when the request then expires), never otherwise, and always happens
even if `JITTER` is 0. Intermediate values fit in signed 64 bits.

## Output

First, one log line per processed attempt, in processing order:

    t=T ID #K RESULT

where `RESULT` is `ok`; or `down` or `limited` followed by ` retry@T'` when a retry was scheduled, by
` gave-up` when the request gave up, or by ` expired` when it expired. Then one line per request, in input
order:

    ID STATUS attempts=K done=T

where `STATUS` is `ok`, `gave-up` or `expired`, `K` is the number of attempts made, and `T` is the time of the
last attempt. Finally

    total ok=X failed=Y attempts=Z

counting requests with status `ok`, requests with any other status, and all attempts. With no requests only the
`total` line is printed.

## Example

Input:

    policy 100 2 1000 4 0 0 7
    down 0 250
    req a 0
    req b 50
    req c 400

Output:

    t=0 a #1 down retry@100
    t=50 b #1 down retry@150
    t=100 a #2 down retry@300
    t=150 b #2 down retry@350
    t=300 a #3 ok
    t=350 b #3 ok
    t=400 c #1 ok
    a ok attempts=3 done=300
    b ok attempts=3 done=350
    c ok attempts=1 done=400
    total ok=3 failed=0 attempts=7
