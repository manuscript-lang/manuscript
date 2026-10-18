import {ReadStream, WriteStream, IoError, read_all, read_line, copy} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import MemoryStream from "./support/streams.ms"

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream("one\r\ntwo\nlast".to_bytes(), 0, closed: false)
    let input = ReadStream(reader)
    if (try read_line(input)) != some("one"): return panic("CRLF line")
    if (try read_line(input)) != some("two"): return panic("LF line")
    if (try read_line(input)) != some("last"): return panic("unterminated line")
    if not (try read_line(input)).is_none(): return panic("EOF")

    let output = MemoryStream("".to_bytes(), 0, closed: false)
    let source = MemoryStream("é🙂".to_bytes(), 0, closed: false)
    if ((try copy(ReadStream(source), WriteStream(output), 6)) != 6): return panic(
        "copy byte count"
    )
    if output.data != "é🙂".to_bytes(): return panic("copy bytes")

test "streams enforce byte limits and preserve original errors":
    let reader = MemoryStream("abc".to_bytes(), 0, closed: false)
    let limited: Result[Bytes, IoError] = error(IoError.LimitExceeded)
    if read_all(ReadStream(reader), 2) != limited: return panic("read budget")

    reader.closed = true
    let closed: Result[Bytes, IoError] = error(IoError.Closed)
    if read_all(ReadStream(reader)) != closed: return panic("read error identity")
