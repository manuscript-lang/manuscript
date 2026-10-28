# conform: tags=control-flow,faults,interfaces,interpolation,lists,modules,mutation,optional,records,stdlib-bytes,stdlib-cleanup,stdlib-fs,stdlib-io,stdlib-testing,testing,tier-io,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/read-line-presence-tail.ms
from "@std/test.ms" import expect_equal, expect_false, expect_ok, expect_true
from "@std/io.ms" import ReadStream, IoError, read_line
from "@std/fs.ms" import filesystem
from "@std/core.ms" import Closeable
from "@std/bytes.ms" import Bytes

type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    var def read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        if self.closed: return error(IoError.Closed)
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.get(self.data.length() - self.offset)
        if count <= 0: return error(IoError.InvalidInput)

        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get().clone()
        self.offset = end
        return ok(chunk)

    var def close() -> Unit: self.closed = True

def present(input: ReadStream, max: Optional[Int] = none) -> Bool:
    if let line = read_line(input, max):
        return line.is_some()

    return False

type LineTailCleanup:
    marker: String

# Cleanup runs on a moved copy, so the marker file is the only way to observe it.
impl Closeable for LineTailCleanup:
    var def close() -> Unit:
        let _written = filesystem().write_file(self.marker, "closed", True)

def with_cleanup(var input: ReadStream, marker: String) -> Bool:
    let _resource = LineTailCleanup(marker)
    if let line = read_line(input):
        return line.is_some()

    return False

def limit(var visits: List[Int]) -> Int:
    visits.append(1)
    return 100

def picked(var visits: List[Int]) -> ReadStream:
    visits.append(2)
    return MemoryStream("a\n".to_bytes(), 0, False)

def reordered(var visits: List[Int]) -> Bool:
    if let line = read_line(max_bytes: limit(var visits), input: picked(var visits)):
        return line.is_some()

    return False

test "presence keeps custom EOF empty CRLF and following text":
    let source = MemoryStream("\r\nλ\nlast".to_bytes(), 0, False)
    let input: ReadStream = source
    present(input) | try expect_true
    (try read_line(input)) | try expect_equal(some("λ"))
    present(input) | try expect_true
    present(input) | try expect_false

test "presence retains custom errors and limits":
    let source = MemoryStream("abc\nx\n".to_bytes(), 0, False)
    var input: ReadStream = source
    present(input, 2) | try expect_false
    input.close()
    present(input) | try expect_false

test "presence retains written argument order and cleanup":
    var input: ReadStream = MemoryStream("b\n".to_bytes(), 0, False)
    var visits: List[Int] = []
    reordered(var visits) | try expect_true
    visits | try expect_equal([1, 2])

    let fs = filesystem()
    let temporary = fs.temporary("manuscript-presence-") | try expect_ok
    let first = f"{temporary.path()}/first"
    let second = f"{temporary.path()}/second"
    with_cleanup(var input, first.clone()) | try expect_true
    fs.read_file(first).is_ok() | try expect_true
    fs.read_file(second).is_ok() | try expect_false
    with_cleanup(var input, second.clone()) | try expect_false
    fs.read_file(second).is_ok() | try expect_true

test "presence and text reads share buffered consumption":
    let fs = filesystem()
    let temporary = fs.temporary("manuscript-presence-") | try expect_ok
    let path = f"{temporary.path()}/lines"
    let _written = fs.write_file(path, "\nλ\r\nlast") | try expect_ok
    let handle = fs.open(path, "r", 384) | try expect_ok
    let input = handle.reader()
    present(input) | try expect_true
    (try read_line(input)) | try expect_equal(some("λ"))
    present(input) | try expect_true
    present(input) | try expect_false
