import panic from "@std/faults.ms"
import Bytes from "@std/bytes.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        return error(IoError.Closed)

    fn close() -> Unit:
        return

test "contract-valued cleanup":
    with file = File(ClosedFile(unit)):
        let read = file.read(max_bytes: 1)
        if read.is_ok():
            return panic(message: "Unexpected case")
        if not (read.unwrap_error() == IoError.Closed):
            return panic(message: "check failed")
