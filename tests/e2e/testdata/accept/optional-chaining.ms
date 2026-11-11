import expect_equal from "@std/test/test.ms"

type Inner:
	count: Int
	tag: String?

type Outer:
	inner: Inner?
	name: String

type Counter:
	calls: Int

fn Counter.scaled(by: Int) Int:
	return self.calls * by

fn count_of(outer: Outer?) Int?:
	return outer?.inner?.count

fn bump(var counter: Counter) Int:
	counter.calls += 100
	return 2

test "a chain is none at the first absent link":
	full: Outer? := Outer(inner: Inner(count: 4, tag: "x"), name: "n")
	hollow: Outer? := Outer(inner: none, name: "n")
	nothing: Outer? := none
	four: Int? := 4
	expect_equal(count_of(full), four)?
	expect_equal(count_of(hollow), none)?
	expect_equal(count_of(nothing), none)?

test "an optional field flattens instead of nesting":
	full: Outer? := Outer(inner: Inner(count: 4, tag: "x"), name: "n")
	untagged: Outer? := Outer(inner: Inner(count: 4, tag: none), name: "n")
	tag := full?.inner?.tag.clone()
	x: String? := "x"
	expect_equal(tag, x)?
	expect_equal(untagged?.inner?.tag, none)?

test "a plain field makes the chain optional":
	present: Outer? := Outer(inner: none, name: "abc")
	absent: Outer? := none
	three: Int? := 3
	expect_equal(present?.name.length(), three)?
	expect_equal(absent?.name.length(), none)?

test "a call's arguments run only when the receiver is present":
	var counter = Counter(calls: 0)
	absent: Counter? := none
	expect_equal(absent?.scaled(bump(var counter)), none)?
	expect_equal(counter.calls, 0)?

	present: Counter? := Counter(calls: 3)
	six: Int? := 6
	expect_equal(present?.scaled(bump(var counter)), six)?
	expect_equal(counter.calls, 100)?
