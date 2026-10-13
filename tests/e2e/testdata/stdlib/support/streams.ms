import {ReadStream, WriteStream, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    fn read(max_bytes: Optional[Int64]) -> Result[Optional[Bytes], IoError]:
        if self.closed: return error(IoError.Closed)
        if self.offset == self.data.length(): return ok(none)

        let remaining = self.data.length() - self.offset
        let requested = max_bytes.unwrap_or(remaining.to_int64())
        if requested <= 0: return error(IoError.InvalidInput)

        var count = remaining

        if requested < remaining.to_int64(): count = requested.to_int().unwrap()

        var end = self.offset + count

        if end > self.data.length(): end = self.data.length()

        let chunk = self.data.slice(start: self.offset, end: end)
        self.offset = end
        return ok(chunk)

    fn close() -> Unit: self.closed = true

impl WriteStream for MemoryStream:
    fn write(data: Bytes) -> Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        self.data = self.data.concat(data)
        return ok(unit)

    fn flush() -> Result[Unit, IoError]:
        if self.closed: return error(IoError.Closed)

        return ok(unit)

    fn close() -> Unit: self.closed = true
