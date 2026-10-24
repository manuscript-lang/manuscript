# conform: tags=control-flow,faults,formatter,interfaces,modules,mutation,optional,parser,records,stdlib-bytes,stdlib-io,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/support/streams.ms
from "@std/io.ms" import ReadStream, WriteStream, IoError
from "@std/bytes.ms" import Bytes

export type MemoryStream:
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

impl WriteStream for MemoryStream:
    var def write(data: String) -> Result[Unit, IoError]:
        return self.write_bytes(data.to_bytes())

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        self.data = self.data.concat(data)
        return ok(())

    def flush() -> Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        return ok(())

    var def close() -> Unit: self.closed = True
