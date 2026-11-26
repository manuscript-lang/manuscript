// conform: tags=control-flow,faults,formatter,modules,stdlib-faults,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=pkg/build/compiler_test.go:280 FuzzCompile
import panic from "@std/core.ms"

test "list" {
	values := [1, 2]
	if not (values.length() == 2) {
		return panic(message: "check failed")
	}
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
