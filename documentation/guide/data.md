+++
title = "Data"
weight = 2
+++

# Data

Orders have a customer, an amount, and a status, and the status carries different details depending on what happened. Manuscript models that with a `type` and an `enum`.

<!-- manuscript-example: {"mode":"run","stdout":"#1 Sam: waiting to ship\n#2 Ada: shipped, tracking ZX81\n#3 Sam: cancelled: out of stock\n#4 Lin: waiting to ship\n3 customers\nSam spent 4350 cents\n"} -->
```manuscript {filename="orders.ms"}
type Order:
    id: Int
    customer: String
    cents: Int
    status: Status = Status.Open

enum Status:
    Open
    Shipped(tracking: String)
    Cancelled(reason: String)

fn label(status: Status) String:
    match status:
        Open:
            return "waiting to ship"
        Shipped(tracking):
            return "shipped, tracking {tracking}"
        Cancelled(reason):
            return "cancelled: {reason}"

export fn main() Int:
    var orders = [
        Order(1, "Sam", 1250),
        Order(2, "Ada", 4000, status: Status.Shipped("ZX81")),
        Order(3, "Sam", 3100, status: Status.Cancelled("out of stock")),
    ]
    orders.append(Order(4, "Lin", 900))

    var spent = Map[String, Int]()
    var customers = Set[String]()
    for order in orders:
        customers.add(order.customer.clone())
        let total = spent.get(order.customer).get(0) + order.cents
        spent.add(order.customer.clone(), total)
        print("#{order.id} {order.customer}: {label(order.status)}")
    print("{customers.length()} customers")
    print("Sam spent {spent.get("Sam").get(0)} cents")
    return 0
```

```text
#1 Sam: waiting to ship
#2 Ada: shipped, tracking ZX81
#3 Sam: cancelled: out of stock
#4 Lin: waiting to ship
3 customers
Sam spent 4350 cents
```

## What to notice

- `type Order` groups named fields. `status: Status = Status.Open` is a default, so `Order(1, "Sam", 1250)` needs no status. Pass a field by name to override it.
- `enum Status` lists the cases an order can be in. `Shipped` and `Cancelled` carry a value; `Open` does not.
- `match` must cover every case. Add a fourth case to `Status` and the compiler points at `label` until you handle it.
- Lists, maps and sets need no import. `spent.get(name)` returns an optional, a value or nothing, and `.get(0)` supplies a fallback for a missing key.
- A `Set` ignores duplicates, so `customers.length()` counts people, not orders.

You may have noticed `.clone()` when a customer name is stored in the set and the map. The compiler requires it, and the next chapters explain why: each value has one owner, and putting a name into a second place needs its own copy.

**Next:** [When things go wrong](when-things-go-wrong.md). **Exact rules:** [Types](../core-language/types/_index.md), [Collections](../core-language/types/collections.md), [Pattern matching](../core-language/control-flow/pattern-matching.md).
