import expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms"
import ReadStream from "@std/io/io.ms"
import lines, from_bytes from "@std/io/streams.ms"
import open, temporary, write_file from "@std/os/fs.ms"

// A line read answers `String?`: an empty line is present, and only the end of the stream is none.
fn present(var input: ReadStream[String]) Bool!:
    let line = try input.read().wait()
    return ok(line.is_some())

test "presence keeps empty CRLF lines and following text":
    var input = lines(from_bytes("\r\nλ\nlast".to_bytes(), 2))
    present(var input) | try expect_ok | try expect_true
    (try input.read().wait()) | try expect_equal("λ")
    present(var input) | try expect_ok | try expect_true
    present(var input) | try expect_ok | try expect_false
    present(var input) | try expect_ok | try expect_false

test "presence retains limits":
    var input = lines(from_bytes("abc\nx\n".to_bytes(), 2), 2)
    present(var input).is_error() | try expect_true

test "presence and text reads share buffered consumption":
    let temporary = temporary("manuscript-presence-") | try expect_ok
    let path = "{temporary.path()}/lines"
    let _written = write_file(path, "\nλ\r\nlast").wait() | try expect_ok
    let handle = open(path, "r", 384) | try expect_ok
    var input = lines(try handle.reader())
    present(var input) | try expect_ok | try expect_true
    (try input.read().wait()) | try expect_equal("λ")
    present(var input) | try expect_ok | try expect_true
    present(var input) | try expect_ok | try expect_false
