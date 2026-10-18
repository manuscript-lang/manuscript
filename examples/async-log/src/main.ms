import {create, LogError} from "@std/log.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import panic from "@std/faults.ms"
import {expect_equal, expect_error} from "@std/testing.ms"
import {sleep, duration} from "@std/time.ms"
import {async_file_transport} from "./async_file_transport.ms"

export fn main() Int:
    return 0

test "records reach the file after flush and close":
    let fs = filesystem()

    with directory = try fs.temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try async_file_transport(path):
            let logger = try create(transport, timestamp: false)
            try logger.info("one")
            try logger.info("two")
            try logger.flush()
            let data = try fs.read_file(path)
            if (
                data.decode_utf8() != some(
                    "\{\"level\":30,\"msg\":\"one\"\}\n\{\"level\":30,\"msg\":\"two\"\}\n"
                )
            ): return panic("flushed")

            try logger.info("three")

        let after = try fs.read_file(path)
        if after.length() != 77: return panic("close drains: {after.length()}")

fn line(text: String) String:
    return "\{\"level\":30,\"msg\":\"{text}\"\}\n"

fn read(path: String) Result[String, Error]:
    let data = try filesystem().read_file(path)
    return ok(data.decode_utf8().get(""))

fn missing(path: String) Bool:
    return filesystem().stat(path, follow_links: false).is_error()

test "size rotation keeps at most max_files files":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try async_file_transport(path, 48, max_files: 3):
            let logger = try create(transport, timestamp: false)
            for name in ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9"]:
                try logger.info(name)

        if try read(path) != line("m8") + line("m9"): return panic("active")
        if try read("{path}.1") != line("m6") + line("m7"): return panic(
            "first rotated"
        )
        if try read("{path}.2") != line("m4") + line("m5"): return panic(
            "second rotated"
        )
        if not missing("{path}.3"): return panic("file beyond max_files kept")

test "a single allowed file is truncated by rotation":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try async_file_transport(path, 30, max_files: 1):
            let logger = try create(transport, timestamp: false)
            try logger.info("a")
            try logger.info("b")

        if try read(path) != line("b"): return panic("active")
        if not missing("{path}.1"): return panic("rotated file kept")

test "age rotation starts a new file":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try async_file_transport(path, max_age: duration(50000000)):
            let logger = try create(transport, timestamp: false)
            try logger.info("old")
            try logger.flush()
            sleep(duration(120000000))
            try logger.info("new")

        if try read("{path}.1") != line("old"): return panic("old file")
        if try read(path) != line("new"): return panic("new file")

test "an existing file's size counts toward rotation":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"
        try filesystem().write_file(path, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")

        with transport = try async_file_transport(path, 40):
            let logger = try create(transport, timestamp: false)
            try logger.info("a")

        if try read("{path}.1") != "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx": return panic(
            "seed rotated"
        )
        if try read(path) != line("a"): return panic("active")

test "invalid limits and a missing directory are rejected":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"
        let zero_bytes = try expect_error(async_file_transport(path, 0))
        try expect_equal(zero_bytes, LogError.InvalidInput)
        let negative_files = try expect_error(async_file_transport(path, max_files: -1))
        try expect_equal(negative_files, LogError.InvalidInput)
        let zero_queue = try expect_error(async_file_transport(path, queue_size: 0))
        try expect_equal(zero_queue, LogError.InvalidInput)
        let zero_age = try expect_error(
            async_file_transport(path, max_age: duration(0))
        )
        try expect_equal(zero_age, LogError.InvalidInput)
        let missing_parent = try expect_error(
            async_file_transport("{directory.path()}/missing/x.ndjson")
        )
        try expect_equal(missing_parent, LogError.FileSystem(FileSystemError.NotFound))

test "a full queue returns LimitExceeded without waiting":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try async_file_transport(path, queue_size: 1):
            var rejected = false
            var attempts = 0

            while not rejected and attempts < 100000:
                attempts += 1
                let outcome = transport.write("x\n")

                if outcome.is_error():
                    if outcome.err() != LogError.LimitExceeded:
                        return panic("unexpected error")

                    rejected = true

            if not rejected: return panic("queue never reported full")

test "writes after close are rejected":
    with directory = try filesystem().temporary("alog-"):
        let path = "{directory.path()}/events.ndjson"
        let transport = try async_file_transport(path)
        transport.close()
        transport.close()
        let cause = try expect_error(transport.write("x\n"))
        try expect_equal(cause, LogError.Closed)
