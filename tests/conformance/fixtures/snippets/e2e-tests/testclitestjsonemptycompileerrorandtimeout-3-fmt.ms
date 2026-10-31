# conform: tags=formatter,modules,parser,stdlib-time,testing,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/cli_json_test.go:128 TestCLITestJSONEmptyCompileErrorAndTimeout
import sleep, nanoseconds from "@std/time.ms"

test "timeout":
    sleep(nanoseconds(1000000000))

test "after":
    return unit
