from "@std/test.ms" import expect_equal, expect_false
from "@std/bytes.ms" import Bytes
from "@std/io.ms" import File
from "@std/io.ms" import IoError

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    def read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        return error(IoError.Closed)

    def close() -> Unit:
        return

test "contract-valued cleanup":
    let opened: File = ClosedFile(())

    with let file = opened:
        let read = file.read(1)
        try expect_false(read.is_ok())
        try expect_equal(read.err(), IoError.Closed)
