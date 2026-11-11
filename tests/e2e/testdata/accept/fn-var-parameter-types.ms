import expect_equal from "@std/test/test.ms"

// A function type may take a parameter `var`: a call through the value passes the caller's
// variable by address, and the callee changes it in place.

fn push_one(var values: List[Int]) Unit:
	values.append(1)

fn bump(var count: Int, by: Int) Unit:
	count += by

type Hooks:
	change: fn(var List[Int]) Unit

type Bag:
	items: List[Int]

fn apply(change: fn(var List[Int]) Unit, var values: List[Int]) Unit:
	change(var values)

test "a named function with a var parameter is a function value":
	var values: List[Int] = []
	change: fn(var List[Int]) Unit := push_one
	change(var values)
	change(var values)
	values | expect_equal([1, 1])?

test "a lambda declares a var parameter":
	var values = [7]
	drop_all := fn(var xs: List[Int]):
		xs = []
	drop_all(var values)
	values.length() | expect_equal(0)?

test "a var parameter of a scalar type changes the caller's variable":
	var count = 1
	add := fn(var n: Int, by: Int):
		n += by
	add(var count, 2)
	bump(var count, 3)
	count | expect_equal(6)?

test "a var parameter passes through a function parameter":
	var values = [5]
	apply(push_one, var values)
	apply(fn(var xs: List[Int]): xs.append(2), var values)
	values | expect_equal([5, 1, 2])?

test "a var parameter changes a field in place":
	var bag = Bag(items: [])
	change: fn(var List[Int]) Unit := push_one
	change(var bag.items)
	bag.items | expect_equal([1])?

test "a function value in a field takes a var argument":
	var values: List[Int] = []
	hooks := Hooks(change: push_one)
	hooks.change(var values)
	values | expect_equal([1])?

fn twice(change: fn(var List[Int]) Unit, var values: List[Int]) Unit:
	// `values` is this function's own var parameter, passed on by address again.
	change(var values)
	change(var values)

test "a var parameter is passed on through another function value":
	var values: List[Int] = []
	twice(push_one, var values)
	values | expect_equal([1, 1])?

test "a var parameter of a one-owner value is not copied":
	var words = ["a"]
	extend := fn(var xs: List[String], more: List[String]):
		xs.extend(more)
	extend(var words, ["b", "c"])
	words | expect_equal(["a", "b", "c"])?
