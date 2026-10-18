import {ReadStream, WriteStream, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"

export type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        if self.closed: return error(IoError.Closed)
        if self.offset == self.data.length(): return ok(none)

        let count = max_bytes.unwrap_or(self.data.length() - self.offset)
        if count <= 0: return error(IoError.InvalidInput)

        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()
        let chunk = self.data.slice(self.offset, end).unwrap()
        self.offset = end
        return ok(chunk)

    fn close() Unit: self.closed = true

impl WriteStream for MemoryStream:
    fn write(data: Bytes) Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        self.data = self.data.concat(data)
        return ok(unit)

    fn flush() Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        return ok(unit)

    fn close() Unit: self.closed = true
