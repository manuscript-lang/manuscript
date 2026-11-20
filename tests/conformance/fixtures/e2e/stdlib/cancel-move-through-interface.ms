// conform: tags=testing,tier-io
// conform: phase=test
import (
	Source from "@std/io/io.ms",
	append_file, temporary from "@std/os/fs.ms",
	expect_ok from "@std/test/test.ms",
)

// A `move` method called through an interface value parks inside the implementation. A
// cancel there must free the implementation's string once (the method owns the payload) and
// the interface box once (the caller owns it); `make cancel-sweep` cancels at every park.
type Counted:
	log: String

fn var Counted.next() Int?!:
	return ok(none)

fn move Counted.close() Void!:
	void append_file(self.log, "x").wait()

type Wrapper:
	source: Source[Int]

fn move Wrapper.close() Void!:
	return self.source.close()

test "a move method through an interface frees its payload and box once":
	dir := temporary("sc-").get()
	log := f"{dir.path()}/r.log"
	void append_file(log, "").wait()
	var wrapper = Wrapper(Counted(log.clone()))
	expect_ok(wrapper.close())?
