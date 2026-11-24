// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

// `x := m.get(k)`, `if x := m.get(k)`, `xs.first()`, `xs.last()`, `m[k]` and
// `m.get_or(k, d)` read the entry in place (a borrow the checker already enforces) instead of
// copying it out of the container. Every shape must still read the same values, and the
// container must be changeable again after the borrow's last use.
type Item:
	sku: String
	qty: Int

type Order:
	id: String
	items: List[Item]
	status: String

type Node:
	name: String
	next: Node?

fn order(move id: String, n: Int) Order:
	var items = List[Item]()
	for i in 0..n:
		items.append(Item(sku: f"{id}-{i}", qty: i + 1))
	return Order(id: id, items: items, status: "placed")

fn by_binding(orders: Map[String, Order], id: String) Int:
	found := orders.get(id)
	if found == null: return 0

	o := found
	return o.items.length() + o.status.length()

fn by_if_let(orders: Map[String, Order], id: String) Int:
	o := orders.get(id)
	if o != null: return o.items.length() + o.status.length()

	return 0

fn by_chain(orders: Map[String, Order], id: String) Int:
	if orders.get(id) == null: return 0

	o := orders[id]
	return o.items.length() + o.status.length()

fn returned(orders: Map[String, Order], id: String) Order?:
	found := orders.get(id)
	return found.clone()

fn take_optional(o: Order?) Int:
	v := o
	if v != null: return v.items.length()

	return -1

fn build() Map[String, Order]:
	var m = Map[String, Order]()
	m.add("a", order("a", 2))
	m.add("b", order("b", 3))
	return m

test "let and if let of a map entry read it in place":
	orders := build()
	expect_equal(by_binding(orders, "a"), 8)?
	expect_equal(by_binding(orders, "zz"), 0)?
	expect_equal(by_if_let(orders, "b"), 9)?
	expect_equal(by_if_let(orders, "zz"), 0)?
	expect_equal(by_chain(orders, "a"), 8)?
	expect_equal(by_chain(orders, "zz"), 0)?
	expect_equal(take_optional(returned(orders, "b")), 3)?
	expect_equal(take_optional(returned(orders, "zz")), -1)?

	found := orders.get("a")
	expect_equal(take_optional(found), 2)?

test "a lent entry of a local var map ends at its last use":
	var m = build()
	a := m.get("a")
	expect_equal((a or panic("called Optional.get() on null")).id, "a")?
	m.add("c", order("c", 1))

	c := m.get("c")
	if c != null:
		expect_equal(
			(c.items.first() or panic("called Optional.get() on null")).sku,
			"c-0",
		)?
	m.remove("a")
	expect_equal(m.get("a") == null, true)?

	o := m["b"]
	expect_equal((o.items.last() or panic("called Optional.get() on null")).qty, 3)?
	m.add("d", order("d", 4))
	expect_equal(m.length(), 3)?

test "first and last lend the element":
	var xs = ["one", "two", "three"]
	first := xs.first()
	last := xs.last()
	expect_equal(first or panic("called Optional.get() on null"), "one")?
	expect_equal(last or panic("called Optional.get() on null"), "three")?

	f := xs.first()
	if f != null:
		expect_equal(f.length(), 3)?
	xs.append("four")
	expect_equal(xs.last() or panic("called Optional.get() on null"), "four")?

	empty := List[String]()
	expect_equal(empty.first() == null, true)?
	expect_equal(empty.last() == null, true)?

	none_here := empty.first()
	if none_here != null:
		expect_equal(none_here, "unreachable")?

test "a temporary container lives as long as its lent entry":
	o := build().get("b")
	expect_equal((o or panic("called Optional.get() on null")).items.length(), 3)?

	item := order("t", 2).items.last()
	if item != null:
		expect_equal(item.sku, "t-1")?

test "get_or reads through the entry":
	var stock = Map[String, Int]()
	stock.add("a", 5)
	expect_equal(stock.get_or(key: "a", fallback: 0), 5)?
	expect_equal(stock.get_or(key: "b", fallback: 7), 7)?

	var names = Map[Int, String]()
	names.add(1, "one")

	one := names.get_or(key: 1, fallback: "none")
	two := names.get_or(key: 2, fallback: f"{1 + 1}")
	expect_equal(one, "one")?
	expect_equal(two, "2")?
	names.add(2, "two")
	expect_equal(names.get_or(key: 2, fallback: ""), "two")?

test "an entry whose optional is boxed is still read correctly":
	var nodes = Map[String, Node]()
	nodes.add("x", Node(name: "x", next: Node(name: "y", next: null)))

	x := nodes.get("x")
	expect_equal(
		(
			(x or panic("called Optional.get() on null")).next
			or panic("called Optional.get() on null")
		).name,
		"y",
	)?

	n := nodes.get("x")
	if n != null:
		expect_equal(n.name, "x")?

	chain := [Node(name: "head", next: null)]
	expect_equal((chain.first() or panic("called Optional.get() on null")).name, "head")?

test "if let over a borrowed optional lends its payload":
	orders := build()
	maybe := orders.get("a")
	o := maybe

	if o != null:
		expect_equal(o.id, "a")?
		expect_equal(o.items.length(), 2)?

	expect_equal(maybe != null, true)?

	text: String? := "hello"
	t := text
	if t != null:
		expect_equal(t.length(), 5)?
	expect_equal(text or panic("called Optional.get() on null"), "hello")?

test "an entry read from a temporary map is an owned copy":
	var kept = Map[String, Order]()
	o := build().get("b")
	if o != null:
		kept.add("b", o.clone())
	expect_equal((kept.get("b") or panic("called Optional.get() on null")).id, "b")?
	expect_equal(
		(
			kept.get("b")
			or panic("called Optional.get() on null")
		).items.length(),
		3,
	)?
