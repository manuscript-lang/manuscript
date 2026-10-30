import FileHandle, filesystem from "@std/fs.ms"
import ReadStream from "@std/io.ms"
import expect_true, expect_ok from "@std/test.ms"

# `FileHandle` is a nominal type with `impl Closeable`, so a binding of one owns the file.
fn view_of(path: String) Result[ReadStream, Error]:
    let file = try filesystem().open(path, "r", 0)
    return ok(file.reader())

test "a file handle binding is closed when its scope ends":
    let temporary = filesystem().temporary("manuscript-owned-") | try expect_ok
    let path = "{temporary.path()}/a.txt"
    try expect_true(filesystem().write_file(path, "x", true).is_ok())

    var view = view_of(path) | try expect_ok
    try expect_true(view.read(none).is_error())

test "closing a file handle by hand is allowed once more at scope end":
    let temporary = filesystem().temporary("manuscript-owned-") | try expect_ok
    let path = "{temporary.path()}/b.txt"
    var file = filesystem().open(path, "w", 420) | try expect_ok
    try expect_true(file.write("hello").is_ok())
    file.close()
