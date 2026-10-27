# conform: tags=control-flow,formatter,match,modules,parser,stdlib-fs,stdlib-testing,testing,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/test_directory_test.go:27 TestTestsRunInProjectDirectory
from "@std/fs.ms" import filesystem
from "@std/test.ms" import expect_true, fail

test "fixture next to the manifest":
    match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024):
        case ok(data):
            if data.length() != 7:
                return fail("wrong fixture size")
        case error(_):
            return fail("fixture not found")
