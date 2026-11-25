// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
	Neg(inner Expr)
}

fn evaluate(expr Expr) Int {
	match expr {
		Num(value) => return value
		Add(left, right) => return evaluate(left) + evaluate(right)
		Neg(inner) => return -evaluate(inner)
	}
}

enum Tree[T] {
	Leaf(value T)
	Branch(left Tree[T], right Tree[T])
}

enum Forest {
	Empty
	More(tree MutualTree)
}

type MutualTree {
	value Int
	rest Forest
}

type Node {
	value Int
	next Node?
}

type DefaultNode {
	value Int
	next DefaultNode?
}

type Link {
	value Int
	next Link?
}

fn Link.equals(other Link) Bool {
	return self.value == other.value
}

fn Link.hash() Int => return self.value

test "recursive alternatives construct match compare and clone" {
	expr := Expr.Add(left: Expr.Num(7), right: Expr.Neg(Expr.Num(2)))
	(evaluate(expr.clone()) != 5 or expr != expr.clone()) | expect_false?

	tree := Tree[Int].Branch(left: Tree[Int].Leaf(1), right: Tree[Int].Leaf(2))
	(
		tree | expect_equal(
			Tree[Int].Branch(
				left: Tree[Int].Leaf(1),
				right: Tree[Int].Leaf(2),
			)
		)?
	)

	forest := Forest.More(MutualTree(value: 3, rest: Forest.Empty))

	match forest {
		More(first) => {
			((first.value != 3 or first.rest != Forest.Empty) | expect_false?)
		}
		Empty => return fail("lost mutual tree")
	}
}

test "recursive records clone into independent storage" {
	child := Node(value: 2, next: null)
	root := Node(value: 1, next: child.clone())
	var alias = root.clone()
	var copy = root.clone()
	alias.value = 3

	var inner = (copy.next or panic("called Optional.get() on null")).clone()
	inner.value = 4
	copy.next = inner
	(
		(
			root.value != 1
			or alias.value != 3
			or (
				copy.next
				or panic("called Optional.get() on null")
			).value != 4
			or child.value != 2
		) | expect_false?
	)
	copy.next = null
	(root.next == null) | expect_false?
}

test "recursive structural equality checks nested and unequal fields" {
	var left = Node(value: 1, next: null)
	var right = Node(value: 1, next: null)
	left.next = left.clone()
	right.next = right.clone()
	left.clone() | expect_equal(right.clone())?

	var copy = left.clone()
	var inner = (copy.next or panic("called Optional.get() on null")).clone()
	inner.value = 2
	copy.next = inner
	(
		(
			left.value != 1
			or copy.value != 1
			or left == copy
			or left != right
		) | expect_false?
	)

	var a = Node(value: 1, next: null)
	b := Node(value: 1, next: a.clone())
	a.next = b
	(right == a) | expect_false?
}

test "recursive domain hashing uses explicit implementations" {
	var left = Link(value: 7, next: null)
	var right = Link(value: 7, next: null)
	left.next = left.clone()
	right.next = right.clone()
	(left != right or left.hash() != right.hash()) | expect_false?

	var values = Map[Link, Int]()
	values.add(key: left.clone(), value: 9)

	var members = Set[Link]([left.clone()])
	(
		(
			(
				values.get(right.clone())
				or panic("called Optional.get() on null")
			) != 9
			or not members.contains(right.clone())
		) | expect_false?
	)
	values.add(key: right.clone(), value: 10)
	members.add(right.clone())
	(
		(
			values.length() != 1
			or members.length() != 1
			or (
				values.get(left.clone())
				or panic("called Optional.get() on null")
			) != 10
		) | expect_false?
	)
}

test "recursive defaults construct independent complete objects" {
	var first = DefaultNode(value: 1)
	second := DefaultNode(value: 2)
	first.next = first.clone()
	(
		(
			(second.next != null)
			or (
				first.next
				or panic("called Optional.get() on null")
			).value != 1
		) | expect_false?
	)
}

type Entry {
	name String
	nickname String?
}

type Person {
	primary Entry?
}

enum NestedOptional {
	Value(value Int??)
}

type NestedResult {
	value Int!Error!Error
}

type Box[T] {
	value T
}

type Pair[T, U] {
	first T
	second U
}

test "finite nested generic composition constructs and extracts values" {
	person := Person(Entry(name: "Ada", nickname: "A"))
	(
		(
			(
				person.primary
				or panic("called Optional.get() on null")
			).nickname
			or panic("called Optional.get() on null")
		) | expect_equal("A")?
	)

	four Int? := 4
	nested_four Int?? := four
	optional := NestedOptional.Value(nested_four)

	match optional {
		Value(value) => {
			expect_equal(value or panic("called Optional.get() on null"), 4)?
		}
	}

	result := NestedResult(ok(ok(5)))

	inner := match result.value {
		ok(inner) => inner.clone()
		error(_) => return fail("unexpected outer result error")
	}

	match inner {
		ok(value) => {
			expect_equal(value, 5)?
		}
		error(_) => return fail("unexpected inner result error")
	}

	box := Box(Box(6))
	box.value.value | expect_equal(6)?

	inner_text String? := "nested"
	pair Pair[Int?, String??] := Pair(first: 7, second: inner_text)
	(
		(
			(pair.first or panic("called Optional.get() on null")) != 7
			or (
				pair.second
				or panic("called Optional.get() on null")
			) != "nested"
		) | expect_false?
	)
}
