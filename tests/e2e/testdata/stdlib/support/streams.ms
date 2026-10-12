import {ReadStream, WriteStream, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type MemoryStream:
    data: Bytes
    offset: Int
    closed: Bool

impl ReadStream for MemoryStream:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        if self.closed: return error(cause: IoError.Closed)
        if self.offset == self.data.length(): return ok(value: none)
        let count = max_bytes.unwrap_or(self.data.length() - self.offset)
        if count <= 0: return error(cause: IoError.InvalidInput)
        var end = self.offset + count
        if end > self.data.length(): end = self.data.length()
        let chunk = self.data.slice(start: self.offset, end: end)
        self.offset = end
        return ok(value: some(value: chunk))
    fn close() -> Unit: self.closed = true

impl WriteStream for MemoryStream:
    fn write(data: Bytes) -> Result[Unit, IoError]:
        if self.closed: return error(cause: IoError.Closed)
        self.data = self.data.concat(data)
        return ok(value: unit)
    fn flush() -> Result[Unit, IoError]:
        if self.closed: return error(cause: IoError.Closed)
        return ok(value: unit)
    fn close() -> Unit: self.closed = true
