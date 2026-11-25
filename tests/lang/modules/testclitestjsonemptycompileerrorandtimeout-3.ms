// conform: tags=modules,stdlib-time,testing,tier-io
// conform: phase=test
// conform: origin=tests/e2e/cli_json_test.go:128 TestCLITestJSONEmptyCompileErrorAndTimeout
import nanoseconds, sleep from "@std/time.ms"

test "timeout" {
	void sleep(nanoseconds(1000000000)).wait()
}

test "after" {
	return
}
