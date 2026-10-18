import {create, LogError} from "@std/log.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import panic from "@std/faults.ms"
import {sleep, duration} from "@std/time.ms"
import {async_file_transport} from "./async_file_transport.ms"

fn value[T, E: Error](result: Result[T, E]) T:
    match result:
        ok(found): return found
        error(cause): return panic(message: cause.message())

export fn main() Int:
    return 0

test "records reach the file after flush and close":
    let fs = filesystem()

    with directory = value(fs.temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(async_file_transport(path)):
            let logger = value(create(transport: transport, timestamp: false))
            value(logger.info(message: "one"))
            value(logger.info(message: "two"))
            value(logger.flush())
            let data = value(fs.read_file(path: path))
            if (
                data.to_string() != some(
                    "\{\"level\":30,\"msg\":\"one\"\}\n\{\"level\":30,\"msg\":\"two\"\}\n"
                )
            ): return panic("flushed")

            value(logger.info(message: "three"))

        let after = value(fs.read_file(path: path))
        if after.length() != 77: return panic("close drains: {after.length()}")

fn line(text: String) String:
    return "\{\"level\":30,\"msg\":\"{text}\"\}\n"

fn read(path: String) String:
    let data = value(filesystem().read_file(path: path))
    return data.to_string().unwrap_or("")

fn missing(path: String) Bool:
    match filesystem().stat(path: path, follow_links: false):
        ok(_): return false
        error(_): return true

test "size rotation keeps at most max_files files":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(async_file_transport(path, max_bytes: 48, max_files: 3)):
            let logger = value(create(transport: transport, timestamp: false))
            for name in ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9"]:
                value(logger.info(message: name))

        if read(path) != line("m8") + line("m9"): return panic("active")
        if read("{path}.1") != line("m6") + line("m7"): return panic("first rotated")
        if read("{path}.2") != line("m4") + line("m5"): return panic("second rotated")
        if not missing("{path}.3"): return panic("file beyond max_files kept")

test "a single allowed file is truncated by rotation":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(async_file_transport(path, max_bytes: 30, max_files: 1)):
            let logger = value(create(transport: transport, timestamp: false))
            value(logger.info(message: "a"))
            value(logger.info(message: "b"))

        if read(path) != line("b"): return panic("active")
        if not missing("{path}.1"): return panic("rotated file kept")

test "age rotation starts a new file":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(async_file_transport(path, max_age: duration(50000000))):
            let logger = value(create(transport: transport, timestamp: false))
            value(logger.info(message: "old"))
            value(logger.flush())
            sleep(duration(120000000))
            value(logger.info(message: "new"))

        if read("{path}.1") != line("old"): return panic("old file")
        if read(path) != line("new"): return panic("new file")

test "an existing file's size counts toward rotation":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"
        value(
            filesystem().write_file(
                path: path,
                data: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx".to_bytes()
            )
        )

        with transport = value(async_file_transport(path, max_bytes: 40)):
            let logger = value(create(transport: transport, timestamp: false))
            value(logger.info(message: "a"))

        if read("{path}.1") != "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx": return panic(
            "seed rotated"
        )
        if read(path) != line("a"): return panic("active")

test "invalid limits and a missing directory are rejected":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        match async_file_transport(path, max_bytes: 0):
            ok(_): return panic("zero max_bytes")
            error(cause):
                if cause != LogError.InvalidInput: return panic("max_bytes cause")

        match async_file_transport(path, max_files: -1):
            ok(_): return panic("negative max_files")
            error(cause):
                if cause != LogError.InvalidInput: return panic("max_files cause")

        match async_file_transport(path, queue_size: 0):
            ok(_): return panic("zero queue")
            error(cause):
                if cause != LogError.InvalidInput: return panic("queue cause")

        match async_file_transport(path, max_age: duration(0)):
            ok(_): return panic("zero age")
            error(cause):
                if cause != LogError.InvalidInput: return panic("age cause")

        match async_file_transport("{directory.path()}/missing/x.ndjson"):
            ok(_): return panic("missing parent")
            error(cause):
                if cause != LogError.FileSystem(FileSystemError.NotFound): return panic(
                    "parent cause"
                )

test "a full queue returns LimitExceeded without waiting":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(async_file_transport(path, queue_size: 1)):
            var rejected = false
            var attempts = 0

            while not rejected and attempts < 100000:
                attempts = attempts + 1

                match transport.write("x\n".to_bytes()):
                    ok(_): continue
                    error(cause):
                        if cause != LogError.LimitExceeded: return panic(
                            "unexpected error"
                        )

                        rejected = true

            if not rejected: return panic("queue never reported full")

test "writes after close are rejected":
    with directory = value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"
        let transport = value(async_file_transport(path))
        transport.close()
        transport.close()

        match transport.write("x\n".to_bytes()):
            ok(_): return panic("write after close")
            error(cause):
                if cause != LogError.Closed: return panic("closed cause")
