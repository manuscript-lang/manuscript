# conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-testing,testing,tier-io,try-result
# conform: phase=check
# conform: origin=tests/e2e/library_project_test.go:32 TestLibraryProjectCommandsAndCache
import value from "@lib/value.ms"
import read_file from "@std/fs.ms"
import fail from "@std/test.ms"

test "root":
    if value() != 3: return fail("bad value")

    let data = try read_file(path: "golden/input.txt", max_bytes: 1024)
    if data.length() != 7: return fail("wrong fixture size")
