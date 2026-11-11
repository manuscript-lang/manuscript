// conform: tags=control-flow,interfaces,modules,optional,records,stdlib-bytes,stdlib-io,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/runtime-4.ms
import (
	Bytes from "@std/bytes.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

interface File:
	fn read(max_bytes: Int?) Bytes?!
	fn close() Unit

type ClosedFile:
	marker: Unit

impl File for ClosedFile:
	fn read(max_bytes: Int?) Bytes?!:
		return error(Error("I/O: resource is closed", kind: "EBADF"))

	fn close() Unit:
		return

test "contract-valued cleanup":
	opened: File := ClosedFile(unit)
	file := opened
	read := file.read(1)
	expect_false(read.is_ok())?
	expect_equal(read.err(), Error("I/O: resource is closed", kind: "EBADF"))?
