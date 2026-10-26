# conform: tags=interfaces,optional,stdlib-io,tier-stdlib,try-result
# conform: phase=run
from "@std/io.ms" import ReadStream, WriteStream, IoError, stdout, read_all, read_line, copy
from "@std/bytes.ms" import Bytes

type Mem:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for Mem:
    var def read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.get(self.data.length() - self.offset)
        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get()
        self.offset = end
        return ok(chunk)

    var def close() -> Unit: self.closed = True

impl WriteStream for Mem:
    var def write(data: String) -> Result[Unit, IoError]:
        return self.write_bytes(data.to_bytes())

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        self.data = self.data.concat(data)
        return ok(())

    def flush() -> Result[Unit, IoError]: return ok(())

    var def close() -> Unit: self.closed = True

def src(text: String) -> ReadStream:
    return Mem(text.to_bytes(), 0, False)

export def main() -> Int:
    let _ = match read_all(src("hello world\nline two\r\nlast"), 100):
        case ok(b): stdout().write(f"all {b.length()}" + "\n")
        case error(e): stdout().write(f"err {e.message()}" + "\n")

    let t = src("hello world\nline two\r\nlast")
    var i = 0

    while i < 4:
        let _ = match read_line(t):
            case ok(l): stdout().write(f"line {l}" + "\n")
            case error(e): stdout().write(f"err {e.message()}" + "\n")

        i = i + 1

    let _ = match read_all(src("abcdefgh"), 5):
        case ok(b): stdout().write(f"all {b.length()}" + "\n")
        case error(e): stdout().write(f"err {e.message()}" + "\n")

    let sink = Mem("".to_bytes(), 0, False)

    let _ = match copy(src("abcdefgh"), sink):
        case ok(n): stdout().write(f"copied {n}" + "\n")
        case error(e): stdout().write(f"err {e.message()}" + "\n")

    let _ = match read_line(src("abcdef"), 3):
        case ok(l): stdout().write(f"line {l}" + "\n")
        case error(e): stdout().write(f"err {e.message()}" + "\n")

    return 0
