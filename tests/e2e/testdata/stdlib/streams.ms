import from_bytes, from_list, map, collect, read_all, copy from "@std/io/streams.ms"
import Bytes from "@std/bytes.ms"
import OpenMode, OpenOptions, open, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"

fn upper(chunk: Bytes) Bytes:
    return chunk.decode_utf8().get("").upper().to_bytes()

test "flows compose stream transforms":
    let temporary = temporary("manuscript-streams-") | try expect_ok
    let path = "{temporary.path()}/pipeline.bin"
    var output = open(path, OpenMode.Write, OpenOptions(permissions: 420)) | try expect_ok
    let source = from_bytes("hello world".to_bytes(), 4)
    let copied = try copy(map(source, upper), try output.writer())
    try output.close()
    try expect_equal(copied, 3)
    try expect_equal(
        (read_file(path: path).wait() | try expect_ok), "HELLO WORLD".to_bytes()
    )

test "from_list and collect bridge lists and streams":
    let doubled = map(from_list([1, 2, 3]), fn(n: Int) Int: n * 2)
    try expect_equal((try collect(doubled, none)), [2, 4, 6])

    let limited = collect(from_list([1, 2, 3]), 2)
    try expect_equal(limited.is_error(), true)

test "read_all joins chunks and enforces its limit":
    try expect_equal(
        (try read_all(from_bytes("abcdef".to_bytes(), 4), none)), "abcdef".to_bytes()
    )
    try expect_equal(read_all(from_bytes("abcdef".to_bytes(), 4), 5).is_error(), true)

test "from_bytes rejects a chunk size below one instead of never ending":
    for size in [0, -1]:
        var source = from_bytes("abc".to_bytes(), size)
        let first = try expect_error(source.next())
        try expect_equal(first.kind, "EINVAL")
