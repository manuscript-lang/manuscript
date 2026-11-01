import expect_equal, expect_ok, expect_true from "@std/test/test.ms"
import open, read_file, temporary from "@std/os/fs.ms"
import connect, listen from "@std/net/net.ms"

# `clone` copies a resource: each copy owns its own descriptor and closes on its own.

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

test "a cloned connection writes after the original closes":
    let listener = try listen("127.0.0.1:0")
    var client = try connect(listener.address(), 2.seconds)
    let server = try listener.accept(2.seconds)
    let writer = try client.clone()
    try client.close()
    try writer.write("hello", 2.seconds)
    try expect_equal((try server.read(5, 2.seconds)).get(), "hello".to_bytes())

test "a closed connection cannot be cloned":
    let listener = try listen("127.0.0.1:0")
    var client = try connect(listener.address(), 2.seconds)
    try client.close()
    try expect_true(client.clone().is_error())
