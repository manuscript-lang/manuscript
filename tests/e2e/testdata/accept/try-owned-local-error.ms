import expect_equal from "@std/test/test.ms"

// `try` of a local this function owns: the error path leaves the function, so the error moves
// into the result and the local is not dropped again (no copy, no double free).
type Door:
	name: String

fn heap(label: String, n: Int) String:
	return "{label}-a-string-long-enough-to-live-on-the-heap-{n}-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn open(name: String, fail: Bool) Door!String:
	if fail: return error(heap("failed", 1))
	return ok(Door(name))

fn length_of(name: String, fail: Bool) Int!String:
	door := open(name, fail)
	length := (try door).name.length()
	return ok(length)

test "an error moves out of an owned local and an ok payload is read in place":
	length_of(heap("door", 2), false).get() | try expect_equal(heap("door", 2).length())
	length_of(heap("door", 3), true).err() | try expect_equal(heap("failed", 1))
