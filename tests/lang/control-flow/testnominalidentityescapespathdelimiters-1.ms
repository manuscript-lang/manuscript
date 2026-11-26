// conform: tags=control-flow,faults,formatter,generics,interfaces,modules,records,stdlib-testing,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/e2e_test.go:381 TestNominalIdentityEscapesPathDelimiters
import expect_true, fail from "@std/test/test.ms"

interface Read {
	fn get() Int
}

type Box[T] {
	value T
}

fn Box[T].get() Int {
	return 3
}

test "encoded nominal identity" {
	box := Box(value: 1)
	view Read := box
	if not (view.get() == 3) {
		return fail("check failed")
	}
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
