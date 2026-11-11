import (
	Closeable from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms",
)

type Resource:
	dir: String
	id: Int

// Close records itself by writing a marker file named after the resource.
fn var Resource.close() Unit!:
	_ := write_file("{self.dir}/{self.id}", "closed", true).wait()

fn closed(dir: String, id: Int) Bool:
	return read_file("{dir}/{id}").wait().is_ok()

fn falls_off_the_end(dir: String) Int:
	r := Resource(dir, 1)
	return r.id

fn returns_early(dir: String, early: Bool) Int:
	r := Resource(dir, 2)
	if early: return 1

	return r.id

fn propagates(dir: String) Int!Error:
	r := Resource(dir, 3)
	failed: Int!Error := error(Error("boom"))
	v := failed?
	return ok(v + r.id)

fn breaks_out(dir: String) Int:
	var i = 0

	while i < 3:
		r := Resource(dir.clone(), 10 + i)
		i += 1
		if i == 2: break
		if r.id == 10: continue

	return i

fn closes_by_hand_too(dir: String) Int:
	var r = Resource(dir, 20)
	r.close().get(none)
	return r.id

test "a resource nothing takes is closed when its scope ends":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(falls_off_the_end(dir.clone()), 1)?
	expect_true(closed(dir, 1))?
	expect_equal(returns_early(dir.clone(), true), 1)?
	expect_true(closed(dir, 2))?

test "an error leaving the scope still closes it":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_true(propagates(dir.clone()).is_error())?
	expect_true(closed(dir, 3))?

test "break and continue close the iteration's resource":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(breaks_out(dir.clone()), 2)?
	expect_true(closed(dir, 10))?
	expect_true(closed(dir, 11))?
	expect_false(closed(dir, 12))?

test "closing by hand does not stop the scope's own close":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(closes_by_hand_too(dir.clone()), 20)?
	expect_true(closed(dir, 20))?

fn reassigns(dir: String) Int:
	var r = Resource(dir.clone(), 30)
	r = Resource(dir, 31)
	return r.id

test "reassigning a resource closes the value it replaces":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(reassigns(dir.clone()), 31)?
	expect_true(closed(dir, 30))?
	expect_true(closed(dir, 31))?

fn open_resource(dir: String, id: Int) Resource:
	return Resource(dir, id)

fn temporary_id(dir: String) Int:
	return open_resource(dir, 40).id

test "an unbound resource temporary is closed at the end of its statement":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(temporary_id(dir.clone()), 40)?
	expect_true(closed(dir, 40))?

fn pops_and_discards(dir: String) Int:
	var rs = [Resource(dir.clone(), 50), Resource(dir, 51)]
	rs.pop()
	return rs.length()

test "a discarded resource result is closed":
	temporary := temporary("manuscript-implicit-") | expect_ok?
	dir := temporary.path()
	expect_equal(pops_and_discards(dir.clone()), 1)?
	expect_true(closed(dir, 51))?
