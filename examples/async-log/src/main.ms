import {create, LogError} from "@std/log.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import panic from "@std/faults.ms"
import {sleep, duration} from "@std/time.ms"
import {async_file_transport} from "./async_file_transport.ms"

fn value[T, E: Error](result: Result[T, E]) T:
    if result.is_error(): return panic(message: result.unwrap_error().message())

    return result.unwrap()

export fn main() Int:
    return 0

test "records reach the file after flush and close":
    let fs = filesystem()

    with directory = fs.temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"

        with transport = async_file_transport(path) | value:
            let logger = create(transport: transport, timestamp: false) | value
            logger.info(message: "one") | value
            logger.info(message: "two") | value
            logger.flush() | value
            let data = fs.read_file(path: path) | value
            if (
                data.to_string() != some(
                    "\{\"level\":30,\"msg\":\"one\"\}\n\{\"level\":30,\"msg\":\"two\"\}\n"
                )
            ): return panic("flushed")

            logger.info(message: "three") | value

        let after = fs.read_file(path: path) | value
        if after.length() != 77: return panic("close drains: {after.length()}")

fn line(text: String) String:
    return "\{\"level\":30,\"msg\":\"{text}\"\}\n"

fn read(path: String) String:
    return filesystem().read_file(path: path)
        | value
        | .to_string().unwrap_or("")

fn missing(path: String) Bool:
    return filesystem().stat(path: path, follow_links: false).is_error()

test "size rotation keeps at most max_files files":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"

        with transport = async_file_transport(path, max_bytes: 48, max_files: 3) | value:
            let logger = create(transport: transport, timestamp: false) | value
            for name in ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9"]:
                logger.info(message: name) | value

        if read(path) != line("m8") + line("m9"): return panic("active")
        if read("{path}.1") != line("m6") + line("m7"): return panic("first rotated")
        if read("{path}.2") != line("m4") + line("m5"): return panic("second rotated")
        if not missing("{path}.3"): return panic("file beyond max_files kept")

test "a single allowed file is truncated by rotation":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"

        with transport = async_file_transport(path, max_bytes: 30, max_files: 1) | value:
            let logger = create(transport: transport, timestamp: false) | value
            logger.info(message: "a") | value
            logger.info(message: "b") | value

        if read(path) != line("b"): return panic("active")
        if not missing("{path}.1"): return panic("rotated file kept")

test "age rotation starts a new file":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"

        with transport = async_file_transport(path, max_age: duration(50000000)) | value:
            let logger = create(transport: transport, timestamp: false) | value
            logger.info(message: "old") | value
            logger.flush() | value
            duration(120000000) | sleep
            logger.info(message: "new") | value

        if read("{path}.1") != line("old"): return panic("old file")
        if read(path) != line("new"): return panic("new file")

test "an existing file's size counts toward rotation":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"
        filesystem().write_file(
            path: path,
            data: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx".to_bytes()
        ) | value
        with transport = async_file_transport(path, max_bytes: 40) | value:
            create(transport: transport, timestamp: false)
                | value
                | .info(message: "a")
                | value
        if read("{path}.1") != "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx": return panic(
            "seed rotated"
        )
        if read(path) != line("a"): return panic("active")

test "invalid limits and a missing directory are rejected":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"
        let zero_bytes = async_file_transport(path, max_bytes: 0)
        if zero_bytes.is_ok(): return panic("zero max_bytes")
        if zero_bytes.unwrap_error() != LogError.InvalidInput: return panic(
            "max_bytes cause"
        )

        let negative_files = async_file_transport(path, max_files: -1)
        if negative_files.is_ok(): return panic("negative max_files")
        if negative_files.unwrap_error() != LogError.InvalidInput: return panic(
            "max_files cause"
        )

        let zero_queue = async_file_transport(path, queue_size: 0)
        if zero_queue.is_ok(): return panic("zero queue")
        if zero_queue.unwrap_error() != LogError.InvalidInput: return panic(
            "queue cause"
        )

        let zero_age = async_file_transport(path, max_age: duration(0))
        if zero_age.is_ok(): return panic("zero age")
        if zero_age.unwrap_error() != LogError.InvalidInput: return panic("age cause")

        let orphan = async_file_transport("{directory.path()}/missing/x.ndjson")
        if orphan.is_ok(): return panic("missing parent")
        if orphan.unwrap_error() != LogError.FileSystem(FileSystemError.NotFound): return panic(
            "parent cause"
        )

test "a full queue returns LimitExceeded without waiting":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"

        with transport = async_file_transport(path, queue_size: 1) | value:
            var rejected = false
            var attempts = 0

            while not rejected and attempts < 100000:
                attempts = attempts + 1
                let written = transport.write("x\n".to_bytes())
                if written.is_ok(): continue
                if written.unwrap_error() != LogError.LimitExceeded: return panic(
                    "unexpected error"
                )

                rejected = true

            if not rejected: return panic("queue never reported full")

test "writes after close are rejected":
    with directory = filesystem().temporary("alog-") | value:
        let path = "{directory.path()}/events.ndjson"
        let transport = async_file_transport(path) | value
        transport.close()
        transport.close()
        let written = transport.write("x\n".to_bytes())
        if written.is_ok(): return panic("write after close")
        if written.unwrap_error() != LogError.Closed: return panic("closed cause")
