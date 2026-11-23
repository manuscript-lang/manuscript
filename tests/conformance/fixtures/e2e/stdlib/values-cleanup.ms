// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	Closeable from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal,
	expect_false,
	expect_not_equal,
	expect_ok,
	expect_true,
	fail from "@std/test/test.ms",
)

type Key:
	id: Int
	label: String

fn Key.equals(other: Key) Bool:
	return self.id == other.id

fn Key.hash() Int: self.id

type Resource:
	dir: String
	id: Int

// Resources own their state, so close records order through the filesystem:
// resource 1 notes whether resource 2 had already closed.
fn move Resource.close() Void!:
	inner_closed := read_file(f"{self.dir}/2").wait().is_ok()
	void write_file(f"{self.dir}/{self.id}", f"{inner_closed}", true).wait()

fn leave(move dir: String) Int:
	_outer := Resource(dir.clone(), 1)
	_inner := Resource(dir, 2)
	return 42

fn propagate(result: Int!) Int!:
	found := result.clone()?
	return ok(found + 1)

test "Optional lazy fallbacks preserve nested absence and payload identity":
	create := fn() Int?: 42
	present: Int? := 0
	missing: Int? := null
	expect_equal(present.or_else(create).get(), 0)?
	expect_equal(missing.or_else(create).get(), 42)?

	nested: Int?? := missing
	expect_true(nested.is_none())?

test "Result propagation and Error views preserve concrete causes":
	failed: Int! := error(Error("JSON: invalid data", kind: "EBADMSG"))
	expect_equal(propagate(failed), failed)?

	success: Int! := ok(3)
	expected: Int! := ok(4)
	expect_equal(propagate(success), expected)?

	view: Error := Error("JSON: invalid data", kind: "EBADMSG")
	expect_not_equal(view.message.length(), 0)?
	expect_equal(view.kind, "EBADMSG")?

test "custom equality and hashing define map key identity":
	first := Key(1, "first")
	second := Key(1, "second")
	expect_false(first != second or first.hash() != second.hash())?

	var map = Map[Key, String]()
	map.add(first.clone(), "a")
	map.add(second, "b")
	expect_false(map.length() != 1 or map.get(first) != "b")?

test "Closeable cleanup runs in reverse order before return delivery":
	temporary := temporary("manuscript-cleanup-") | expect_ok?
	dir := temporary.path()
	expect_equal(leave(dir.clone()), 42)?
	expect_equal((read_file(f"{dir}/1").wait()?), Bytes([116, 114, 117, 101]))?
	expect_equal((read_file(f"{dir}/2").wait()?), Bytes([102, 97, 108, 115, 101]))?
