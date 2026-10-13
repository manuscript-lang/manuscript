# Invoice batch

A small shop turns a day's orders into customer invoices. Standard input holds the configuration, the
product catalog and the order lines. Bad lines are reported, not fatal. All text is ASCII. All money is
integer cents; never use floating point, and round exactly as described.

## Input

Lines are numbered from 1 (physical lines). Trim spaces and tabs from both ends of each line, then:

- Empty lines and lines starting with `#` are ignored.
- A line that starts with `[` is a section header. Exactly `[config]`, `[catalog]` or `[orders]` selects that
  section; any other header records `line N: unknown section` and leaves no active section.
- Any other line belongs to the active section; with no active section it is ignored silently.

Sections may appear in any order and repeat. All configuration and catalog lines apply to all orders,
wherever they appear. Orders are processed in file order after everything has been read.

**Money** (a *decimal*) is 1 to 5 digits, optionally followed by `.` and 1 or 2 digits (`12`, `0.5`, `99999.99`),
converted to cents (`0.5` is 50 cents). A *percent* is 1 to 3 digits optionally followed by `.` and 1 or 2
digits, with a value of at most 100, converted to basis points (hundredths of a percent): `7.5` is 750,
`20` is 2000, `100` is 10000.

### `[config]`

Tokens are separated by runs of spaces and tabs.

- `tax CLASS PERCENT`: sets the tax rate for a tax class (any token). A later line for the same class replaces
  the earlier one. Classes without a rate are taxed at 0.
- `shipping FEE FREE_OVER`: both are money decimals (cents). Default: no shipping fee. Last valid line wins.

Any other line, or one with a malformed number, records `line N: bad config`.

### `[catalog]`

`SKU|NAME|PRICE|CLASS`: exactly 4 parts separated by `|`, each trimmed. `SKU` is non-empty with no space or
tab, `NAME` and `CLASS` are non-empty (`NAME` may contain spaces), `PRICE` is a money decimal. Otherwise record
`line N: bad product`. A SKU already defined by an earlier valid line records `line N: duplicate sku` and the
first definition stays.

### `[orders]`

`CUSTOMER|SKU|QTY` or `CUSTOMER|SKU|QTY|DISCOUNT`: 3 or 4 parts separated by `|`, each trimmed. The first
failing check decides the message, recorded as `line N: <message>`:

1. wrong number of parts, or empty `CUSTOMER`: `bad order`
2. `QTY` is not 1 to 4 digits with a value of at least 1: `bad quantity`
3. `DISCOUNT` is present but is not 1 to 3 digits with a value of at most 100 (a whole percent): `bad discount`
4. `SKU` is not in the catalog: `unknown sku`

## Pricing

For each valid order line, with `price` the product's cents:

- `gross = price * qty`
- `discount = round(gross * pct / 100)` where `pct` is the whole discount percent (0 when absent)
- `net = gross - discount`
- `tax = round(net * rate / 10000)` where `rate` is the basis points of the product's class

`round(a / b)` means integer division rounding halves up, that is `(a + b/2) / b` using integer division
(`b` is even here). Tax is rounded per line, never per invoice.

Each customer with at least one valid line gets one invoice: `subtotal` is the sum of the line nets, `tax` the
sum of the line taxes, `shipping` is the configured fee when a fee is configured and `subtotal` is **less than**
`FREE_OVER` (otherwise 0), and `total = subtotal + tax + shipping`.

## Output

Invoices in ascending byte order of the customer name (names are case-sensitive). Money is printed as
`D.CC` (cents always two digits, no thousands separators):

    INVOICE <customer>
      <sku> <name> x<qty> @ <unit price> = <net>[ (-<discount> discount)]
      subtotal <subtotal>
      tax <tax>
      shipping <shipping>
      total <total>

Item lines follow the order lines of that customer in file order; the discount note appears only when the
discount is above 0. `qty` is printed as an integer without leading zeros. After the invoices print

    summary: invoices=<count> grand_total=<sum of totals> problems=<number of problems>

and, if there are problems, `problems:` followed by the messages in file order, each indented by 2 spaces.

Example input:

    [config]
    tax A 20
    tax B 7.5
    shipping 4.99 50
    [catalog]
    pen|Blue pen|1.20|A
    pad|Note pad|3.35|B
    [orders]
    ann|pen|10
    ann|pad|3|10
    bob|pen|1
    bob|ink|2
    cy|pad|x

Output:

    INVOICE ann
      pen Blue pen x10 @ 1.20 = 12.00
      pad Note pad x3 @ 3.35 = 9.04 (-1.01 discount)
      subtotal 21.04
      tax 3.08
      shipping 4.99
      total 29.11
    INVOICE bob
      pen Blue pen x1 @ 1.20 = 1.20
      subtotal 1.20
      tax 0.24
      shipping 4.99
      total 6.43
    summary: invoices=2 grand_total=35.54 problems=2
    problems:
      line 12: unknown sku
      line 13: bad quantity
