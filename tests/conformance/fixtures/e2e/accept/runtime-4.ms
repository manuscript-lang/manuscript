# conform: tags=control-flow,interfaces,modules,optional,records,stdlib-bytes,stdlib-io,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/runtime-4.ms
import expect_equal, expect_false from "@std/test/test.ms"
import Bytes from "@std/bytes.ms"
import File from "@std/io/io.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Int?) Bytes?!:
        return error(Error("I/O: resource is closed", kind: ErrorCategory.Closed))

    fn close() Unit:
        return

test "contract-valued cleanup":
    let opened: File = ClosedFile(unit)
    let file = opened
    let read = file.read(1)
    try expect_false(read.is_ok())
    try expect_equal(read.err(), Error("I/O: resource is closed", kind: ErrorCategory.Closed))
