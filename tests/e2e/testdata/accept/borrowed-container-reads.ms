from "@std/testing.ms" import expect_equal
from "@std/collections.ms" import range

# `let x = m.get(k)`, `if let x = m.get(k)`, `xs.first()`, `xs.last()`, `m.get(k).get()` and
# `m.get_or(k, d)` read the entry in place (a borrow the checker already enforces) instead of
# copying it out of the container. Every shape must still read the same values, and the
# container must be changeable again after the borrow's last use.
type Item:
    sku: String
    qty: Int

type Order:
    id: String
    items: List[Item]
    status: String

type Node:
    name: String
    next: Optional[Node]

def order(id: String, n: Int) -> Order:
    var items = List[Item]()
    for i in range(0, n):
        items.append(Item(sku: f"{id}-{i}", qty: i + 1))
    return Order(id: id, items: items, status: "placed")

def by_binding(orders: Map[String, Order], id: String) -> Int:
    let found = orders.get(id)
    if found.is_none():
        return 0

    let o = found.get()
    return o.items.length() + o.status.length()

def by_if_let(orders: Map[String, Order], id: String) -> Int:
    if let o = orders.get(id):
        return o.items.length() + o.status.length()

    return 0

def by_chain(orders: Map[String, Order], id: String) -> Int:
    if orders.get(id).is_none():
        return 0

    let o = orders.get(id).get()
    return o.items.length() + o.status.length()

def returned(orders: Map[String, Order], id: String) -> Optional[Order]:
    let found = orders.get(id)
    return found.clone()

def take_optional(o: Optional[Order]) -> Int:
    if let v = o:
        return v.items.length()

    return -1

def build() -> Map[String, Order]:
    var m = Map[String, Order]()
    m.add("a", order("a", 2))
    m.add("b", order("b", 3))
    return m

test "let and if let of a map entry read it in place":
    let orders = build()
    expect_equal(by_binding(orders, "a"), 8)
    expect_equal(by_binding(orders, "zz"), 0)
    expect_equal(by_if_let(orders, "b"), 9)
    expect_equal(by_if_let(orders, "zz"), 0)
    expect_equal(by_chain(orders, "a"), 8)
    expect_equal(by_chain(orders, "zz"), 0)
    expect_equal(take_optional(returned(orders, "b")), 3)
    expect_equal(take_optional(returned(orders, "zz")), -1)

    let found = orders.get("a")
    expect_equal(take_optional(found), 2)

test "a lent entry of a local var map ends at its last use":
    var m = build()
    let a = m.get("a")
    expect_equal(a.get().id, "a")
    m.add("c", order("c", 1))
    if let c = m.get("c"):
        expect_equal(c.items.first().get().sku, "c-0")
    m.remove("a")
    expect_equal(m.get("a").is_none(), True)

    let o = m.get("b").get()
    expect_equal(o.items.last().get().qty, 3)
    m.add("d", order("d", 4))
    expect_equal(m.length(), 3)

test "first and last lend the element":
    var xs = ["one", "two", "three"]
    let first = xs.first()
    let last = xs.last()
    expect_equal(first.get(), "one")
    expect_equal(last.get(), "three")
    if let f = xs.first():
        expect_equal(f.length(), 3)
    xs.append("four")
    expect_equal(xs.last().get(), "four")

    let empty = List[String]()
    expect_equal(empty.first().is_none(), True)
    expect_equal(empty.last().is_none(), True)
    if let none_here = empty.first():
        expect_equal(none_here, "unreachable")

test "a temporary container lives as long as its lent entry":
    let o = build().get("b")
    expect_equal(o.get().items.length(), 3)
    if let item = order("t", 2).items.last():
        expect_equal(item.sku, "t-1")

test "get_or reads through the entry":
    var stock = Map[String, Int]()
    stock.add("a", 5)
    expect_equal(stock.get_or(key: "a", fallback: 0), 5)
    expect_equal(stock.get_or(key: "b", fallback: 7), 7)

    var names = Map[Int, String]()
    names.add(1, "one")

    let one = names.get_or(key: 1, fallback: "none")
    let two = names.get_or(key: 2, fallback: f"{1 + 1}")
    expect_equal(one, "one")
    expect_equal(two, "2")
    names.add(2, "two")
    expect_equal(names.get_or(key: 2, fallback: ""), "two")

test "an entry whose optional is boxed is still read correctly":
    var nodes = Map[String, Node]()
    nodes.add("x", Node(name: "x", next: some(Node(name: "y", next: none))))

    let x = nodes.get("x")
    expect_equal(x.get().next.get().name, "y")
    if let n = nodes.get("x"):
        expect_equal(n.name, "x")

    let chain = [Node(name: "head", next: none)]
    expect_equal(chain.first().get().name, "head")

test "if let over a borrowed optional lends its payload":
    let orders = build()
    let maybe = orders.get("a")

    if let o = maybe:
        expect_equal(o.id, "a")
        expect_equal(o.items.length(), 2)

    expect_equal(maybe.is_some(), True)

    let text: Optional[String] = some("hello")
    if let t = text:
        expect_equal(t.length(), 5)
    expect_equal(text.get(), "hello")
