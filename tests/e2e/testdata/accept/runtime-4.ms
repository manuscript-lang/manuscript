import expect_equal, expect_false from "@std/test.ms"
import Bytes from "@std/bytes.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Int?) Bytes?!IoError:
        return error(IoError.Closed)

    fn close() Unit:
        return

test "contract-valued cleanup":
    let opened: File = ClosedFile(unit)
    let file = opened
    let read = file.read(1)
    try expect_false(read.is_ok())
    try expect_equal(read.err(), IoError.Closed)
