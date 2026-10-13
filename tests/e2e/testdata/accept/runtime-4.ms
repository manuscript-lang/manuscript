import panic from "@std/faults.ms"

import Bytes from "@std/bytes.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        return error(IoError.Closed)

    fn close() -> Unit:
        return

test "contract-valued cleanup":
    with file = File(ClosedFile(unit)):
        match file.read(max_bytes: 1):
            ok(_):
                return panic(message: "Unexpected case")

            error(cause):
                if not (cause == IoError.Closed):
                    return panic(message: "check failed")
