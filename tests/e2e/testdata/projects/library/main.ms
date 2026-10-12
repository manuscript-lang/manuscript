import panic from "@std/faults.ms"

import Process from "@std/cli.ms"
import Result from "@std/result.ms"
import LibraryError from "@std/errors.ms"
import uuid_v4 from "@std/random.ms"
import secure_int from "@std/random.ms"
import format_timestamp from "@std/time.ms"
import parse_timestamp from "@std/time.ms"

fn exercise(process: Process, path: String) -> Result[Unit, LibraryError]:
    let written = try process.filesystem.write_file(path: path, data: "hello".to_bytes(), replace: false)
    if not (try process.filesystem.read_file(path: path, max_bytes: 5) == "hello".to_bytes()):
        return panic(message: "check failed")
    let info = try process.filesystem.stat(path: path, follow_links: true)
    if not (info.size == 5):
        return panic(message: "check failed")
    if not (not info.directory):
        return panic(message: "check failed")
    let bytes = try process.entropy.bytes(count: 16)
    if not (bytes.length() == 16):
        return panic(message: "check failed")
    let identifier = try uuid_v4(entropy: process.entropy)
    if not (identifier.byte_length() == 36):
        return panic(message: "check failed")
    let random = try secure_int(entropy: process.entropy, min: -2, max_exclusive: 3)
    if not (random >= -2 and random < 3):
        return panic(message: "check failed")
    let now = process.wall_clock.now()
    if not (try parse_timestamp(text: format_timestamp(value: now)) == now):
        return panic(message: "check failed")
    if not (process.system.info().cpu_count > 0):
        return panic(message: "check failed")
    let removed = try process.filesystem.remove(path: path, recursive: false)
    return ok(value: unit)

export fn main(process: Process) -> Int:
    match process.arguments.get(index: 0):
        some(path):
            match exercise(process: process, path: path):
                ok(_):
                    return 0
                error(_):
                    return 1
        none:
            return 2
