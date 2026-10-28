# conform: tags=control-flow,formatter,interfaces,modules,optional,parser,records,stdlib-bytes,stdlib-io,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/runtime-4.ms
import {expect_equal, expect_false} from "@std/test.ms"
import Bytes from "@std/bytes.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        return error(IoError.Closed)

    fn close() Unit:
        return

test "contract-valued cleanup":
    let opened: File = ClosedFile(unit)

    with let file = opened:
        let read = file.read(1)
        try expect_false(read.is_ok())
        try expect_equal(read.err(), IoError.Closed)
