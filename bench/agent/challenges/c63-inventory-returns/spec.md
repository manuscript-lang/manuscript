# Inventory and orders: add returns

The workspace holds a working warehouse tool (stock, prices, orders, cancel, ship, report). It reads commands from standard input, one per line, and answers each with one line (`report` answers with several). Its current behavior is correct and must not change except as this ticket says.

## Ticket

Customers send shipped goods back. Add a `return` command and account for refunds in the report.

- `return <id> <sku> <qty>` (4 tokens). The usual check order applies: unknown command, wrong token count (`error: usage`), argument syntax, existence, then the rules.
  - Syntax, in this order: `error: bad order id`, `error: bad sku`, `error: bad quantity` (same definitions as for `order`).
  - Existence: `error: unknown order <id>`.
  - Rules, in this order: a `placed` order prints `error: order <id> is not shipped`; a cancelled order prints `error: order <id> is cancelled`; a sku that is not one of the order's items prints `error: sku <sku> not in order <id>`; a quantity above what is still returnable (the ordered quantity minus the quantity already returned for that sku in that order) prints `error: cannot return <qty> of <sku> (<left> left)`.
  - On success the returned units go back into stock and the refund is `round_half_up(line_cost * qty / ordered_qty)` cents, where `line_cost` is what that line cost when the order was placed (including any discount, using the price at that moment) and `ordered_qty` is the line's ordered quantity; use integer arithmetic (`(line_cost * qty * 2 + ordered_qty) / (2 * ordered_qty)`). Prints `ok refund=<money>`.
- `report` changes: the line `revenue=` is now the sum of the totals of shipped orders minus all refunds, and a new line `refunded=<money>` (the sum of all refunds) follows it. Nothing else in `report` changes.

Example input:

    stock A 20
    price A 250
    order o1 A:12
    ship o1
    return o1 A 5
    return o1 A 8
    report

Output:

    ok A stock=20
    ok
    ok o1 total=27.00
    ok
    ok refund=11.25
    error: cannot return 8 of A (7 left)
    A stock=13 price=2.50 reserved=0
    orders placed=0 shipped=1 cancelled=0
    revenue=15.75
    refunded=11.25
