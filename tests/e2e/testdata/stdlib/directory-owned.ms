import filesystem from "@std/fs.ms"
import {expect_equal, expect_false, expect_ok, expect_true} from "@std/test.ms"

# `Directory` and `TemporaryDirectory` are nominal types with `impl Closeable`, so a binding owns them.
fn leaves_a_temporary() Result[String, Error]:
    let temporary = try filesystem().temporary("manuscript-owned-")
    let path = temporary.path()
    try filesystem().write_file("{path}/a.txt", "x", true)
    return ok(path)

test "a temporary directory binding is removed when its scope ends":
    let path = leaves_a_temporary() | try expect_ok
    try expect_false(filesystem().stat(path, true).is_ok())

fn counts_entries(path: String) Result[Int, Error]:
    let cursor = try filesystem().open_directory(path)
    var seen = 0

    while true:
        let next = try cursor.read()
        if next.is_none():
            break

        seen += 1

    return ok(seen)

test "a directory cursor reads its children and closes at scope end":
    let temporary = filesystem().temporary("manuscript-owned-") | try expect_ok
    let path = temporary.path()
    try expect_true(filesystem().write_file("{path}/a.txt", "x", true).is_ok())
    try expect_true(filesystem().write_file("{path}/b.txt", "y", true).is_ok())
    counts_entries(path) | try expect_ok | try expect_equal(2)
