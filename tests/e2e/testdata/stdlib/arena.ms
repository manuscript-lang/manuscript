import (
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
	Arena, Id from "@std/collections/arena.ms",
)

type Node:
	name: String
	next: Id[Node]?

test "add returns handles that read back their values":
	var a = Arena[Node]()
	first := a.add(Node(name: "a", next: none))
	second := a.add(Node(name: "b", next: first))
	try expect_equal(a.get(first).get().name, "a")

	link := a.get(second).get().next.get()
	try expect_equal(a.get(link).get().name, "a")

test "a removed handle is stale and its slot is reused with a new generation":
	var a = Arena[Node]()
	old := a.add(Node(name: "a", next: none))
	removed := a.remove(old)
	try expect_equal(removed.get().name, "a")
	try expect_false(a.contains(old))

	fresh := a.add(Node(name: "b", next: none))
	try expect_false(a.contains(old))
	try expect_true(a.contains(fresh))
	try expect_equal(a.length(), 1)
	try expect_true(a.remove(old).is_none())

test "update changes the value in place":
	var a = Arena[Node]()
	id := a.add(Node(name: "a", next: none))
	try expect_true(a.update(id, fn(var n: Node) Unit: n.name = "z"))
	try expect_equal(a.get(id).get().name, "z")
