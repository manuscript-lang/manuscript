import OpenMode, OpenOptions, open, temporary, write_file from "@std/os/fs.ms"
import ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import expect_true, expect_ok from "@std/test/test.ms"

// `FileHandle` is a nominal type with `impl Closeable`, so a binding of one owns the file.
fn view_of(path: String) ReadStream[Bytes]!:
    file := try open(path, OpenMode.Read)
    return ok(try file.reader())

test "a file handle binding is closed when its scope ends":
    temporary := temporary("manuscript-owned-") | try expect_ok
    path := "{temporary.path()}/a.txt"
    try expect_true(write_file(path, "x", true).wait().is_ok())

    var view = view_of(path) | try expect_ok
    try expect_true(view.next().is_ok())

test "closing a file handle by hand is allowed once more at scope end":
    temporary := temporary("manuscript-owned-") | try expect_ok
    path := "{temporary.path()}/b.txt"
    var file = open(path, OpenMode.Write, OpenOptions(permissions: 420)) | try expect_ok
    try expect_true(file.write("hello").is_ok())
    try file.close()
