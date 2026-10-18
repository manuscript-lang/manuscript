# Inventory and orders

A small warehouse tool reads commands, one per line, and answers each with one line (the `report` command
answers with several). Blank lines (empty or only spaces) are ignored. A command is split on single
spaces; the first token is the command name (case-sensitive).

Definitions:

- A **sku** is one or more characters from `A-Z`, `0-9` and `-`.
- An **order id** is one or more characters from `a-z`, `0-9` and `-`.
- A **number** is 1 to 7 ASCII decimal digits (leading zeros allowed). Quantities must be from 1 to
  100000; prices (in cents) from 0 to 10000000.
- Money is printed as dollars with two decimals (`1234.05`) from integer cents.

For every command the checks are made in this order and the first failure prints its error line and
changes nothing: (1) unknown command name: `error: unknown command`; (2) wrong token count: `error: usage`;
(3) argument syntax; (4) existence of the things named; (5) the rules of the command.

## Commands

- `stock <sku> <qty>` (3 tokens): `error: bad sku`, then `error: bad quantity`. Adds `qty` units to the
  sku's stock, creating the sku with price 0 if it is new. Prints `ok <sku> stock=<new stock>`.
- `price <sku> <cents>` (3 tokens): `error: bad price` if `cents` is not a valid price. The sku must exist
  (`error: unknown sku <sku>`; a malformed sku is simply unknown). Sets the unit price. Prints `ok`.
- `order <id> <item> <item> ...` (at least 3 tokens): each item is `<sku>:<qty>`.
  - `error: bad order id` if the id is malformed; then `error: order <id> already exists` if that id was
    used before (even for a cancelled order).
  - Every item must be well formed (exactly one `:`, a valid sku, a valid quantity); the first bad item
    in the line prints `error: bad item <token>` (the token as written).
  - Then the items are examined in the order given, and the first problem found prints an error: a sku that
    already appeared earlier in this order is `error: duplicate sku <sku>`; a sku that does not exist is
    `error: unknown sku <sku>`; a quantity above the current stock is
    `error: insufficient stock for <sku> (have <stock>, need <qty>)`.
  - If everything is fine, stock is reduced for all items at once (all-or-nothing) and the order is
    `placed`. Each line costs `qty * price` cents; if `qty >= 10` the line gets a 10% discount, i.e. it costs
    `round_half_up(qty * price * 90 / 100)` cents. The order total is the sum of its lines, computed with the
    prices at this moment. Prints `ok <id> total=<money>`.
- `cancel <id>` (2 tokens): the order must exist (`error: unknown order <id>`). A `placed` order becomes
  `cancelled` and its quantities return to stock; prints `ok`. A shipped order prints
  `error: order <id> already shipped`, a cancelled one `error: order <id> already cancelled`.
- `ship <id>` (2 tokens): the order must exist (`error: unknown order <id>`). A `placed` order becomes
  `shipped`; prints `ok`. A shipped order prints `error: order <id> already shipped`; a cancelled one
  `error: order <id> is cancelled`.
- `report` (1 token): prints, in this order, one line per sku in byte order of the sku:
  `<sku> stock=<stock> price=<money> reserved=<units in placed orders>`; then
  `orders placed=<a> shipped=<b> cancelled=<c>`; then `revenue=<money>`, the sum of the totals of shipped
  orders.

Example input:

    stock WIDGET 100
    stock GADGET-2 5
    price WIDGET 250
    price GADGET-2 1999
    order o1 WIDGET:10 GADGET-2:2
    order o2 GADGET-2:4
    ship o1
    cancel o1
    report

Output:

    ok WIDGET stock=100
    ok GADGET-2 stock=5
    ok
    ok
    ok o1 total=62.48
    error: insufficient stock for GADGET-2 (have 3, need 4)
    ok
    error: order o1 already shipped
    GADGET-2 stock=3 price=19.99 reserved=0
    WIDGET stock=90 price=2.50 reserved=0
    orders placed=0 shipped=1 cancelled=0
    revenue=62.48
