# conform: tags=interfaces,optional,stdlib-io,tier-stdlib,try-result
# conform: phase=run
import (
    ReadStream,
    WriteStream,
    IoError,
    stdout,
    read_all,
    read_line,
    copy
) from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"

type Mem:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for Mem:
    var fn read(max_bytes: Int?) Bytes?!IoError:
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.get(self.data.length() - self.offset)
        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get()
        self.offset = end
        return ok(chunk)

    var fn close() Unit: self.closed = true

impl WriteStream for Mem:
    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!IoError:
        self.data = self.data.concat(data)
        return ok(unit)

    fn flush() Unit!IoError: return ok(unit)

    var fn close() Unit: self.closed = true

fn src(text: String) ReadStream:
    return Mem(text.to_bytes(), 0, false)

export fn main() Int:
    let _ = match read_all(src("hello world\nline two\r\nlast"), 100):
        ok(b): stdout().write("all {b.length()}" + "\n")
        error(e): stdout().write("err {e.message()}" + "\n")

    let t = src("hello world\nline two\r\nlast")
    var i = 0

    while i < 4:
        let _ = match read_line(t):
            ok(l): stdout().write("line {l}" + "\n")
            error(e): stdout().write("err {e.message()}" + "\n")

        i = i + 1

    let _ = match read_all(src("abcdefgh"), 5):
        ok(b): stdout().write("all {b.length()}" + "\n")
        error(e): stdout().write("err {e.message()}" + "\n")

    let sink = Mem("".to_bytes(), 0, false)

    let _ = match copy(src("abcdefgh"), sink):
        ok(n): stdout().write("copied {n}" + "\n")
        error(e): stdout().write("err {e.message()}" + "\n")

    let _ = match read_line(src("abcdef"), 3):
        ok(l): stdout().write("line {l}" + "\n")
        error(e): stdout().write("err {e.message()}" + "\n")

    return 0
