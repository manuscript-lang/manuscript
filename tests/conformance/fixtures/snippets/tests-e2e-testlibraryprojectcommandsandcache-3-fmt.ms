# conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-testing,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/library_project_test.go:32 TestLibraryProjectCommandsAndCache
import value from "@lib/value.ms"
import filesystem from "@std/fs.ms"
import fail from "@std/testing.ms"

test "root":
    if value() != 3: return fail("bad value")

    let data = try filesystem().read_file(path: "golden/input.txt", max_bytes: 1024)
    if data.length() != 7: return fail("wrong fixture size")
