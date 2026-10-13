# Invoice report

Turn an export of invoice line items into a billing report. All money is handled exactly, in integer
cents, with the rounding rules below.

## Input

Three preamble lines, then CSV rows:

    tax_rate=8.25
    as_of=2024-03-15
    invoice,date,customer,sku,qty,unit_price,discount_pct
    INV-001,2024-01-15,"Acme, Inc.",WIDGET,3,19.99,10
    ...

- Line 1: `tax_rate=` followed by a percentage: 1 to 3 digits, optionally `.` and 1 or 2 digits, at most
  `100.00`. Otherwise print `error: bad tax_rate` and nothing else.
- Line 2: `as_of=` followed by a valid date `YYYY-MM-DD`. Otherwise `error: bad as_of` and nothing else.
- Line 3: exactly the header shown above. Otherwise `error: bad header` and nothing else. (If a preamble
  line is missing, the first check that fails decides; checks are made in the order tax_rate, as_of,
  header.)
- Valid dates: year 1900 to 2100, month 01 to 12, day valid for the month (Gregorian leap years: divisible
  by 4, except centuries not divisible by 400). Format is exactly 4-2-2 digits.
- Every later line is a row, except blank lines (empty or only spaces), which are ignored. Line numbers
  below are physical 1-based line numbers (the header is line 3, blank lines count).

## Rows

A row has exactly 7 comma-separated fields. A field may be wrapped in double quotes, in which case it may
contain commas, and a literal quote is written as two quotes (`"Say ""hi"""` is `Say "hi"`). An unquoted
field must not contain a quote character; after a closing quote only a comma or the end of the line may
follow. Fields are not trimmed; spaces are part of the value. A row that cannot be split this way, or does
not have 7 fields, is rejected with reason `malformed row`.

Otherwise the fields are checked in this order; the first failing check rejects the row with that reason:

1. `invoice` empty: `empty invoice id`
2. `date` not a valid date: `bad date`
3. `customer` empty: `empty customer`
4. `sku` empty: `empty sku`
5. `qty` not 1 to 5 ASCII digits with a value from 1 to 10000: `bad qty`
6. `unit_price` not 1 to 7 digits optionally followed by `.` and 1 or 2 digits: `bad price`
7. `discount_pct` not 1 to 3 digits with a value from 0 to 100: `bad discount`
8. an earlier accepted row has the same `invoice` but a different `date` or `customer`:
   `conflicting invoice header` (the first accepted row of an invoice defines its date and customer)

Rejected rows do not count toward anything else.

## Calculation

For each accepted row, `line_net = round_half_up(qty * unit_price_cents * (100 - discount_pct) / 100)`
(an exact tie at .5 cents rounds up). Per invoice: `subtotal` is the sum of its line nets,
`tax = round_half_up(subtotal * tax_rate / 100)` (computed exactly from the rate in hundredths of a
percent), `total = subtotal + tax`. The invoice is due 30 days after its date (calendar days, across month
and year ends). If `as_of` is later than the due date the invoice is `OVERDUE <n> days` where n is the
number of days between the due date and `as_of` (always written `days`, even for 1); otherwise `OPEN`.

## Output

1. One line per rejected row, in input order: `rejected line <N>: <reason>`
2. One line per invoice, in byte order of the invoice id:
   `invoice <id> | <date> | <customer> | items=<rows> | subtotal=<S> | tax=<T> | total=<G> | due=<date> | <status>`
3. One line per customer, in byte order of the name (names are compared exactly, case-sensitively):
   `customer <name> | invoices=<count> | total=<sum of their invoice totals>`
4. Always last: `summary | invoices=<count> | rejected=<count> | total=<sum of all invoice totals>`

Money is written as dollars with exactly two decimals (`1234.05`). Customer names are printed raw, without
CSV quoting.

Example input:

    tax_rate=8.25
    as_of=2024-03-15
    invoice,date,customer,sku,qty,unit_price,discount_pct
    INV-001,2024-01-15,"Acme, Inc.",WIDGET,3,19.99,10
    INV-001,2024-01-15,"Acme, Inc.",GADGET,1,5.00,0
    INV-002,2024-03-10,Zed,WIDGET,2,19.99,0
    INV-002,2024-03-11,Zed,WIDGET,2,19.99,0
    INV-003,2024-02-30,Zed,WIDGET,1,1,0

Output:

    rejected line 7: conflicting invoice header
    rejected line 8: bad date
    invoice INV-001 | 2024-01-15 | Acme, Inc. | items=2 | subtotal=58.97 | tax=4.87 | total=63.84 | due=2024-02-14 | OVERDUE 30 days
    invoice INV-002 | 2024-03-10 | Zed | items=1 | subtotal=39.98 | tax=3.30 | total=43.28 | due=2024-04-09 | OPEN
    customer Acme, Inc. | invoices=1 | total=63.84
    customer Zed | invoices=1 | total=43.28
    summary | invoices=2 | rejected=2 | total=107.12
