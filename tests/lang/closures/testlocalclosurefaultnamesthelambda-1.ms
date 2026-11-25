// conform: tags=closures,faults,formatter,modules,stdlib-faults,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=tests/e2e/local_closures_test.go:11 TestLocalClosureFaultNamesTheLambda
import panic from "@std/core.ms"

fn run() Int {
	boom := fn(value Int) Int => panic(message: "closure failed")
	return boom(value: 1)
}

test "fault" {
	run()
}
// expect-exit: 1
// expect-tests: passed=0 failed=1
