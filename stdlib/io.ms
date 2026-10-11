# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export interface File:
    fn close() -> Unit
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]

export interface Files:
    fn open(path: String) -> Result[File & Shareable, IoError]

export type IoError:
    case Closed
    case InvalidInput
    case Unavailable
    case Failed(message: String)

export interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]

export interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
    fn write(data: Bytes) -> Result[Unit, IoError]

export fn copy(input: ReadStream & Shareable, output: WriteStream & Shareable, max_bytes: Int) -> Result[Int, LibraryError]

export fn read_all(input: ReadStream & Shareable, max_bytes: Int) -> Result[Bytes, LibraryError]

export fn read_line(input: ReadStream & Shareable, max_bytes: Int) -> Result[Optional[String], LibraryError]
