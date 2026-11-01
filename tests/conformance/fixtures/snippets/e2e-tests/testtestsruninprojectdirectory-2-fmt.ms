# conform: tags=control-flow,formatter,match,modules,parser,stdlib-fs,stdlib-testing,testing,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/test_directory_test.go:27 TestTestsRunInProjectDirectory
import read_file from "@std/os/fs.ms"
import expect_true, fail from "@std/test/test.ms"

test "fixture next to the manifest":
    match read_file(path: "golden/input.txt", max_bytes: 1024):
        ok(data):
            if data.length() != 7:
                return fail("wrong fixture size")
        error(_):
            return fail("fixture not found")
