import {duration, timestamp} from "@std/time.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

fn verify_file_offsets() -> Result[Unit, FileSystemError]:
    let files = filesystem()
    let offset: Int64 = 3000000000

    with directory = try files.temporary("wide-contract-"):
        with file = try files.open(directory.path() + "/probe", "w+", 384):
            let position = try file.seek(offset, 0)
            if position != offset:
                return panic("file offset narrowed")

            let absent = try file.read_at(offset, max_bytes: 1)
            if not absent.is_empty():
                return panic("read beyond EOF changed")

            let start = try file.seek(0, 0)
            let count = try file.write(Bytes([7]))
            if start != 0 or count != 1:
                return panic("wide file count changed")

            let info = try file.stat()
            if info.size + 1 != 2 or info.inode + 0 != info.inode:
                return panic("file metadata identity narrowed")

    return ok(unit)

test "time preserves counts beyond signed32":
    let nanoseconds: Int64 = 3000000000
    let interval = duration(nanoseconds)
    if interval.to_nanoseconds() != nanoseconds or interval.to_seconds() != 3.0:
        return panic("duration count narrowed")
    if interval.multiply(2).to_nanoseconds() != 6000000000:
        return panic("duration arithmetic narrowed")

    let future = timestamp(4102444800, 123).unwrap()
    if future.unix_seconds() != 4102444800 or future.nanoseconds() != 123:
        return panic("timestamp contract narrowed")

    let units: Int64 = 3
    if units.seconds.to_nanoseconds() != nanoseconds:
        return panic("wide unit receiver changed")

test "file offsets and sizes have explicit wide identities":
    verify_file_offsets().unwrap()
