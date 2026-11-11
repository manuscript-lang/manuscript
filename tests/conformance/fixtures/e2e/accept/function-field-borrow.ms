// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Loader:
	load: fn(Int) Int

fn run(l: Loader) Int:
	load := l.load
	return load(2)

test "a let of a function-valued field borrows it":
	l := Loader(fn n: n + 1)
	expect_equal(run(l), 3)?
	expect_equal(l.load(5), 6)?
