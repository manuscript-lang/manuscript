# conform: tags=control-flow,match,modules,stdlib-fs,stdlib-testing,testing,tier-io
# conform: phase=test
# conform: origin=tests/e2e/test_directory_test.go:27 TestTestsRunInProjectDirectory
import filesystem from "@std/fs.ms"
import {expect_true, fail} from "@std/test.ms"

test "fixture next to the manifest":
    match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024):
        ok(data):
            if data.length() != 7:
                return fail("wrong fixture size")
        error(_):
            return fail("fixture not found")
