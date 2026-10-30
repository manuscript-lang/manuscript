# conform: tags=modules,stdlib-time,testing,tier-io
# conform: phase=test
# conform: origin=tests/e2e/cli_json_test.go:128 TestCLITestJSONEmptyCompileErrorAndTimeout
import sleep, nanoseconds from "@std/time.ms"

test "timeout":
    sleep(nanoseconds(1000000000))

test "after":
    return unit
