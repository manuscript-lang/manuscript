# conform: tags=formatter,modules,parser,stdlib-io,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/cli_json_test.go:70 TestCLITestJSONPreservesOutputsFailuresAndLocations
from "@std/io.ms" import stdout, stderr
from "@std/testing.ms" import fail

test "first=pass":
    let _out = stdout().write(data: "PASS fake test\nuser stdout\n")
    let _err = stderr().write(data: "user stderr\n")

test "second=fails":
    return fail("expected failure")

test "third=after":
    return ()
