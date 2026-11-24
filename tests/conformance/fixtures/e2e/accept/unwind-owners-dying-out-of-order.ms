// conform: tags=testing,tier-io
// conform: phase=test
import (
	panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_fault from "@std/test/test.ms",
)

// Owners die in a different order than they were registered while later calls can
// fault. Each dead owner's cleanup entry is cancelled and the live ones stay
// registered, so every resource closes exactly once whether the function returns or
// faults.
type Res:
	id: Int
	log: String

fn move Res.close() Void!:
	append_file(self.log, f"{self.id},").wait()?

fn touch(r: Res, fail: Bool) Int:
	if fail: panic("touch failed")
	return r.id

fn run(log: String, fail: Bool) Int:
	a := Res(1, log.clone())
	b := Res(2, log.clone())
	c := Res(3, log.clone())
	d := Res(4, log.clone())
	x := touch(b, false)
	y := touch(d, false)
	z := touch(a, fail)
	return x + y + z + touch(c, false)

fn closed(log: String) String!:
	bytes := read_file(log).wait()?
	return ok(bytes.decode_utf8() or "")

test "resources registered together close once when the function returns":
	temp := temporary("unwind-order-")?
	log := f"{temp.path()}/log"
	expect_equal(run(log.clone(), false), 10)?

	text := closed(log)?
	expect_equal(text.length(), 8)?
	for id in ["1,", "2,", "3,", "4,"]:
		expect_equal(text.contains(id), true)?

test "resources registered together close once when a later call faults":
	temp := temporary("unwind-order-")?
	log := f"{temp.path()}/log"
	message := expect_fault(fn: void run(log.clone(), true))?
	expect_equal(message, "touch failed")?

	text := closed(log)?
	expect_equal(text.length(), 8)?
	for id in ["1,", "2,", "3,", "4,"]:
		expect_equal(text.contains(id), true)?
