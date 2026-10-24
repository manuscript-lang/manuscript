# conform: tags=modules,stdlib-time,testing,tier-io
# conform: phase=test
# conform: origin=tests/e2e/cli_json_test.go:128 TestCLITestJSONEmptyCompileErrorAndTimeout
from "@std/time.ms" import sleep, duration

test "timeout":
    sleep(duration(nanoseconds: 1000000000))

test "after":
    return ()
