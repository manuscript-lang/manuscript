# conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-testing,testing,tier-io,try-result
# conform: phase=check
# conform: origin=tests/e2e/library_project_test.go:32 TestLibraryProjectCommandsAndCache
from "@lib/value.ms" import value
from "@std/fs.ms" import filesystem
from "@std/test.ms" import fail

test "root":
    if value() != 3: return fail("bad value")

    let data = try filesystem().read_file(path: "golden/input.txt", max_bytes: 1024)
    if data.length() != 7: return fail("wrong fixture size")
