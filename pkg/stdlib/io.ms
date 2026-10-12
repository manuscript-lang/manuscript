# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export interface File:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

export interface Files:
    fn open(path: String) -> Result[File, IoError]

export type IoError:
    case Closed
    case InvalidInput
    case Unavailable
    case InvalidData
    case LimitExceeded
    case Failed(message: String)

export interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

export interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
    fn write(data: Bytes) -> Result[Unit, IoError]

export fn copy(input: ReadStream, output: WriteStream, max_bytes: Optional[Int] = none) -> Result[Int, IoError]

export fn read_all(input: ReadStream, max_bytes: Optional[Int] = none) -> Result[Bytes, IoError]

export fn read_line(input: ReadStream, max_bytes: Optional[Int] = none) -> Result[Optional[String], IoError]

impl Error for IoError:
    fn message() -> String

export fn stdin() -> ReadStream

export fn stdout() -> WriteStream

export fn stderr() -> WriteStream

export fn files() -> Files
