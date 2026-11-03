import expect_equal, expect_ok from "@std/test/test.ms"
import open, read_file, temporary from "@std/os/fs.ms"

// `clone` copies a resource: each copy owns its own descriptor and closes on its own. A `Connection` has no clone: its
// `input` and `output` streams are the two owners (see net.ms).

test "a cloned file handle writes through its own descriptor after the original closes":
    let temporary = temporary("manuscript-dup-") | try expect_ok
    let path = "{temporary.path()}/a.txt"
    var file = open(path, "w", 420) | try expect_ok
    var copy = file.clone() | try expect_ok
    try file.write("one ")
    try file.close()
    try copy.write("two")
    try copy.close()
    try expect_equal(try read_file(path), "one two".to_bytes())
