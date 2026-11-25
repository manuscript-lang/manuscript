// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Link {
	ref Int
}

fn follow(ref Link) Int {
	return ref.ref
}

test "ref is an ordinary name" {
	ref := Link(ref: 3)
	expect_equal(follow(ref), 3)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
