// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Node:
	value Int
	next Node?

fn parse(text String) Int!:
	return ok_or(text.parse_int(), Error("not a number"))

fn parse_digits(text String) String!:
	return ok(parse(text)?.to_string())

fn value_of(n Node?) Int?:
	return n?.value

fn second_of(n Node?) Int?:
	return n?.next?.value

fn make() Node:
	return Node(1, Node(2, null))

fn first_value() Int?:
	return make().next?.value

fn mark(var marks List[Int], n Node?) Void:
	marks.append(n?.value)
	marks.append(99)

test "a member after ? on a Result reads the unwrapped value":
	expect_equal(parse_digits("42")?, "42")?
	expect_equal(parse_digits("x").is_error(), true)?

test "? on an Optional gives the value, or leaves the function with none":
	expect_equal(value_of(make()), 1)?
	expect_equal(value_of(null), null)?
	expect_equal(second_of(make()), 2)?
	expect_equal(second_of(Node(1, null)), null)?
	expect_equal(first_value(), 2)?

test "? on an absent Optional returns early from a function returning nothing":
	var present List[Int] = []
	mark(present, make())
	expect_equal(present, [1, 99])?

	var absent List[Int] = []
	mark(absent, null)
	expect_equal(absent, [])?
