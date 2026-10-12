import {ReadStream, WriteStream, IoError, read_all, read_line, copy} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import MemoryStream from "./support/streams.ms"
import value from "./support/results.ms"

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream(data: "one\r\ntwo\nlast".to_bytes(), offset: 0, closed: false)
    let input = ReadStream(value: reader)
    if value(read_line(input: input)) != some(value: "one"): return panic("CRLF line")
    if value(read_line(input: input)) != some(value: "two"): return panic("LF line")
    if value(read_line(input: input)) != some(value: "last"): return panic("unterminated line")
    if not value(read_line(input: input)).is_none(): return panic("EOF")
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let source = MemoryStream(data: "é🙂".to_bytes(), offset: 0, closed: false)
    if value(copy(input: ReadStream(value: source), output: WriteStream(value: output), max_bytes: some(value: 6))) != 6: return panic("copy byte count")
    if output.data != "é🙂".to_bytes(): return panic("copy bytes")

test "streams enforce byte limits and preserve original errors":
    let reader = MemoryStream(data: "abc".to_bytes(), offset: 0, closed: false)
    let limited: Result[Bytes, IoError] = error(cause: IoError.LimitExceeded)
    if read_all(input: ReadStream(value: reader), max_bytes: some(value: 2)) != limited: return panic("read budget")
    reader.closed = true
    let closed: Result[Bytes, IoError] = error(cause: IoError.Closed)
    if read_all(input: ReadStream(value: reader)) != closed: return panic("read error identity")

