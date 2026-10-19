import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {ReadStream, IoError, read_line} from "@std/io.ms"
import filesystem from "@std/fs.ms"
import Closeable from "@std/cleanup.ms"
import Bytes from "@std/bytes.ms"

type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        if self.closed: return error(IoError.Closed)
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.get(self.data.length() - self.offset)
        if count <= 0: return error(IoError.InvalidInput)

        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()
        let chunk = self.data.slice(self.offset, end).get()
        self.offset = end
        return ok(chunk)

    fn close() Unit: self.closed = true

fn present(input: ReadStream, max: Optional[Int] = none) Bool:
    if let line = read_line(input, max):
        return line.is_some()

    return false

type LineTailCleanup:
    visits: List[Int]

impl Closeable for LineTailCleanup:
    fn close() Unit:
        self.visits.append(3)

fn with_cleanup(input: ReadStream, visits: List[Int]) Bool:
    with resource = LineTailCleanup(visits):
        if let line = read_line(input):
            return line.is_some()

        return false

fn limit(visits: List[Int]) Int:
    visits.append(1)
    return 100

fn picked(input: ReadStream, visits: List[Int]) ReadStream:
    visits.append(2)
    return input

fn reordered(input: ReadStream, visits: List[Int]) Bool:
    if let line = read_line(max_bytes: limit(visits), input: picked(input, visits)):
        return line.is_some()

    return false

test "presence keeps custom EOF empty CRLF and following text":
    let source = MemoryStream("\r\nλ\nlast".to_bytes(), 0, false)
    let input = ReadStream(source)
    present(input) | try expect_true
    (try read_line(input)) | try expect_equal(expected: some("λ"))
    present(input) | try expect_true
    present(input) | try expect_false
    source.offset | try expect_equal(expected: source.data.length())

test "presence retains custom errors and limits":
    var source = MemoryStream("abc\nx\n".to_bytes(), 0, false)
    let input = ReadStream(source)
    present(input, 2) | try expect_false
    source.closed = true
    present(input) | try expect_false

test "presence retains written argument order and cleanup":
    let source = MemoryStream("a\nb\n".to_bytes(), 0, false)
    let input = ReadStream(source)
    let visits: List[Int] = []
    reordered(input, visits) | try expect_true
    visits | try expect_equal(expected: [1, 2])
    with_cleanup(input, visits) | try expect_true
    with_cleanup(input, visits) | try expect_false
    visits | try expect_equal(expected: [1, 2, 3, 3])

test "presence and text reads share buffered consumption":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-presence-") | try expect_ok):
        let path = "{temporary.path()}/lines"
        let written = fs.write_file(path, "\nλ\r\nlast") | try expect_ok

        with handle = (fs.open(path, "r", 384) | try expect_ok):
            let input = handle.reader()
            present(input) | try expect_true
            (try read_line(input)) | try expect_equal(expected: some("λ"))
            present(input) | try expect_true
            present(input) | try expect_false
