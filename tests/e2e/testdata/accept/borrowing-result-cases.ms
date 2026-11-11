import expect_equal from "@std/test/test.ms"

// A function that relays the error of a borrowed Result but builds its own ok payload returns a
// borrowing result: the error case borrows the argument (no copy), the ok case is owned.
fn grow(value: String!String) String!String:
	output := value?
	return ok(output + "x")

fn heap(label: String, n: Int) String:
	return "{label}-a-string-long-enough-to-live-on-the-heap-{n}-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn by_match(value: String!String) Int:
	match grow(value):
		ok(text): return text.length()
		error(cause): return cause.length()

fn by_binding(value: String!String) Int:
	result := grow(value)

	match result:
		ok(text): return text.length()
		error(cause): return cause.length()

fn relay(value: String!String) String!String:
	text := grow(value)?
	return ok(text + "y")

fn pass_on(value: String!String) String!String:
	text := grow(value)?
	return ok(text)

fn describe(value: String!String) String:
	return "{grow(value)}"

test "a borrowing result reads and drops only the cases it owns":
	good: String!String := ok(heap("ok", 1))
	bad: String!String := error(heap("bad", 2))
	by_match(good) | expect_equal(heap("ok", 1).length() + 1)?
	by_match(bad) | expect_equal(heap("bad", 2).length())?
	by_binding(good) | expect_equal(heap("ok", 1).length() + 1)?
	by_binding(bad) | expect_equal(heap("bad", 2).length())?

test "try relays a borrowed error and takes an owned ok payload":
	good: String!String := ok(heap("ok", 3))
	bad: String!String := error(heap("bad", 4))
	relay(good).get() | expect_equal(heap("ok", 3) + "xy")?
	relay(bad).err() | expect_equal(heap("bad", 4))?
	pass_on(good).get() | expect_equal(heap("ok", 3) + "x")?
	pass_on(bad).err() | expect_equal(heap("bad", 4))?

test "a borrowing result is passed to a reader as an ordinary Result":
	bad: String!String := error(heap("bad", 5))
	describe(bad) | expect_equal("error({heap("bad", 5)})")?
