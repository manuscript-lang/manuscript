# Shipping quotes

A fulfilment tool turns a CSV of orders into shipping quotes. All money is integer cents with the rounding
rules below; "round half up" means a value exactly halfway rounds up.

## Input

The first line must be exactly

    order,country,weight_g,service,declared_cents

otherwise print `error: bad header` and nothing else (this includes empty input). Every later line is a
row, except blank lines (empty or only spaces), which are ignored. Line numbers below are physical 1-based
line numbers (the header is line 1, blank lines count).

A row has exactly 5 comma-separated fields (no quoting); any other count is rejected as `malformed row`.
Otherwise the fields are checked in this order, and the first failure rejects the row with that reason:

1. `order`: one or more of `A-Z a-z 0-9 -`, else `bad order`
2. `country`: exactly two uppercase ASCII letters, else `bad country`
3. `weight_g`: 1 to 5 ASCII digits with a value from 1 to 30000, else `bad weight`
4. `service`: `standard`, `express` or `overnight`, else `bad service`
5. `declared_cents`: 1 to 8 ASCII digits with a value up to 10000000, else `bad declared`
6. `order` seen on an earlier accepted row: `duplicate order`
7. `service` is `overnight` and the zone is not 1: `overnight unavailable`

## Pricing

- **Zone** from the country: `US` is zone 1; `CA`, `MX` zone 2; `AT BE DE ES FR IE IT NL PT SE` zone 3;
  every other country zone 4.
- **Band** is `ceil(weight_g / 500)`.
- **Base rate** in cents is `start + step * (band - 1)` with (start, step) = zone 1: (499, 120);
  zone 2: (899, 180); zone 3: (1499, 250); zone 4: (2199, 400).
- **Service factor**: `standard` x1; `express` x1.5, `overnight` x3. Express is
  `round_half_up(rate * 3 / 2)`; overnight is `rate * 3`. The result is the `base` charge.
- **Free shipping**: a `standard` order in zone 1 with `weight_g <= 2000` and `declared_cents >= 5000` has
  `base = 0` and no fuel surcharge.
- **Fuel** is `round_half_up(base * 8 / 100)` (0 for free shipping, which has base 0 anyway).
- **Insurance** is `0` if `declared_cents <= 10000`, otherwise `round_half_up(declared_cents / 100)`.
- `total = base + fuel + insurance`.

## Output

One line for each non-blank row after the header, in input order:

- rejected: `line <N>: rejected: <reason>`
- accepted: `<order> | zone=<Z> | band=<B> | base=<money> | fuel=<money> | insurance=<money> | total=<money>`

Then three lines in this order, always present:
`service standard: orders=<n> total=<money>`, `service express: ...`, `service overnight: ...`
(accepted orders per service and the sum of their totals), and finally
`summary: orders=<accepted> rejected=<rejected> total=<money>`.

Money is dollars with exactly two decimals (`12.05`).

Example input:

    order,country,weight_g,service,declared_cents
    A-1,US,1200,standard,6000
    A-2,DE,2600,express,20000
    A-3,US,100,overnight,0
    A-4,FR,100,overnight,0
    A-5,us,100,standard,0
    A-1,US,100,standard,0
    A-6,JP,30001,standard,0

Output:

    A-1 | zone=1 | band=3 | base=0.00 | fuel=0.00 | insurance=0.00 | total=0.00
    A-2 | zone=3 | band=6 | base=41.24 | fuel=3.30 | insurance=2.00 | total=46.54
    A-3 | zone=1 | band=1 | base=14.97 | fuel=1.20 | insurance=0.00 | total=16.17
    line 5: rejected: overnight unavailable
    line 6: rejected: bad country
    line 7: rejected: duplicate order
    line 8: rejected: bad weight
    service standard: orders=1 total=0.00
    service express: orders=1 total=46.54
    service overnight: orders=1 total=16.17
    summary: orders=3 rejected=4 total=62.71
