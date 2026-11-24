// conform: tags=control-flow,scope-cleanup,tier-stdlib,testing
// conform: phase=test
import (
	ReadStream from "@std/io/io.ms",
	expect_equal from "@std/test/test.ms",
)

type Src:
	at: Int

fn var Src.next() String?!:
	if self.at >= 3: return ok(null)

	self.at += 1
	return ok("x")

fn move Src.close() Void!:
	return ok()

fn make() ReadStream[String]:
	return ReadStream[String](Src(0))

fn read_all() List[String]!:
	var out: List[String] = []
	for s in make():
		out.append(s)
	return ok(out)

test "loop over a call":
	got := read_all()?
	expect_equal(got.length(), 3)?
