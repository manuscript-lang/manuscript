// conform: tags=diagnostics
// conform: phase=check
import filesystem from "@std/os/fs.ms"
import expect_true, fail from "@std/test/test.ms"

test "fixture next to the manifest":
    match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024):
        ok(data):
            if data.length() != 7:
                return fail("wrong fixture size")
        error(_):
            return fail("fixture not found")
