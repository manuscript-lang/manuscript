# conform: tags=control-flow,diagnostics,faults,interfaces,modules,mutation,optional,records,stdlib-bytes,stdlib-io,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/stdlib/support/streams.ms
import ReadStream, WriteStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"

export type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    var fn read(max_bytes: Int?) Bytes?!:
        if self.closed: return error(Error("I/O: resource is closed", kind: ErrorCategory.Closed))
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.get(self.data.length() - self.offset)
        if count <= 0: return error(Error("I/O: invalid input", kind: ErrorCategory.InvalidInput))

        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get().clone()
        self.offset = end
        return ok(chunk)

    var fn close() Unit: self.closed = true

impl WriteStream for MemoryStream:
    var fn write(data: String) Unit!:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!:
        if self.closed: return error(Error("I/O: resource is closed", kind: ErrorCategory.Closed))

        self.data = self.data.concat(data)
        return ok(unit)

    fn flush() Unit!:
        if self.closed: return error(Error("I/O: resource is closed", kind: ErrorCategory.Closed))

        return ok(unit)

    var fn close() Unit: self.closed = true
