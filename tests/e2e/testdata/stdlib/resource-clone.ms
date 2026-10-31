import expect_equal, expect_ok, expect_true from "@std/test.ms"
import filesystem from "@std/fs.ms"
import network from "@std/net.ms"

# `clone` copies a resource: each copy owns its own descriptor and closes on its own.

test "a cloned file handle writes through its own descriptor after the original closes":
    let temporary = filesystem().temporary("manuscript-dup-") | try expect_ok
    let path = "{temporary.path()}/a.txt"
    var file = filesystem().open(path, "w", 420) | try expect_ok
    var copy = file.clone() | try expect_ok
    try file.write("one ")
    file.close()
    try copy.write("two")
    copy.close()
    try expect_equal(try filesystem().read_file(path), "one two".to_bytes())

test "a cloned connection writes after the original closes":
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    var client = try net.connect(listener.address(), 2.seconds)
    let server = try listener.accept(2.seconds)
    let writer = try client.clone()
    client.close()
    try writer.write("hello", 2.seconds)
    try expect_equal((try server.read(5, 2.seconds)).get(), "hello".to_bytes())

test "a closed connection cannot be cloned":
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    var client = try net.connect(listener.address(), 2.seconds)
    client.close()
    try expect_true(client.clone().is_error())
