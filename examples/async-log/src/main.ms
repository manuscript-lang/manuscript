import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {create, LogError} from "@std/log.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import {sleep, duration} from "@std/time.ms"
import {async_file_transport} from "./async_file_transport.ms"

fn value[T, E: Error](result: Result[T, E]) Result[T, Error]:
    match result:
        ok(found): return ok(found)
        error(cause): return error(cause)

export fn main() Int:
    return 0

test "records reach the file after flush and close":
    let fs = filesystem()

    with directory = try value(fs.temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = try value(async_file_transport(path)):
            let logger = try value(create(transport: transport, timestamp: false))
            try value(logger.info(message: "one"))
            try value(logger.info(message: "two"))
            try value(logger.flush())
            let data = try value(fs.read_file(path: path))
            try expect_false(
                (
                    data.decode_utf8() != some(
                        "\{\"level\":30,\"msg\":\"one\"\}\n\{\"level\":30,\"msg\":\"two\"\}\n"
                    )
                )
            )
            try value(logger.info(message: "three"))

        let after = try value(fs.read_file(path: path))
        if after.length() != 77: return fail("close drains: {after.length()}")

fn line(text: String) String:
    return "\{\"level\":30,\"msg\":\"{text}\"\}\n"

fn read(path: String) Result[String, Error]:
    let data = try value(filesystem().read_file(path: path))
    return ok(data.decode_utf8().get(""))

fn missing(path: String) Bool:
    match filesystem().stat(path: path, follow_links: false):
        ok(_): return false
        error(_): return true

test "size rotation keeps at most max_files files":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = try value(
            async_file_transport(path, max_bytes: 48, max_files: 3)
        ):
            let logger = try value(create(transport: transport, timestamp: false))
            for name in ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9"]:
                try value(logger.info(message: name))

        (try read(path)) | try expect_equal(expected: line("m8") + line("m9"))
        (try read("{path}.1")) | try expect_equal(expected: line("m6") + line("m7"))
        (try read("{path}.2")) | try expect_equal(expected: line("m4") + line("m5"))
        (not missing("{path}.3")) | try expect_false

test "a single allowed file is truncated by rotation":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = try value(
            async_file_transport(path, max_bytes: 30, max_files: 1)
        ):
            let logger = try value(create(transport: transport, timestamp: false))
            try value(logger.info(message: "a"))
            try value(logger.info(message: "b"))

        (try read(path)) | try expect_equal(expected: line("b"))
        (not missing("{path}.1")) | try expect_false

test "age rotation starts a new file":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = try value(
            async_file_transport(path, max_age: duration(50000000))
        ):
            let logger = try value(create(transport: transport, timestamp: false))
            try value(logger.info(message: "old"))
            try value(logger.flush())
            sleep(duration(120000000))
            try value(logger.info(message: "new"))

        (try read("{path}.1")) | try expect_equal(expected: line("old"))
        (try read(path)) | try expect_equal(expected: line("new"))

test "an existing file's size counts toward rotation":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"
        try value(
            filesystem().write_file(
                path: path,
                data: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            )
        )

        with transport = try value(async_file_transport(path, max_bytes: 40)):
            let logger = try value(create(transport: transport, timestamp: false))
            try value(logger.info(message: "a"))

        (try read("{path}.1")) | try expect_equal(
            expected: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        )
        (try read(path)) | try expect_equal(expected: line("a"))

test "invalid limits and a missing directory are rejected":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        match async_file_transport(path, max_bytes: 0):
            ok(_): return fail("zero max_bytes")
            error(cause):
                try expect_equal(cause, LogError.InvalidInput)

        match async_file_transport(path, max_files: -1):
            ok(_): return fail("negative max_files")
            error(cause):
                try expect_equal(cause, LogError.InvalidInput)

        match async_file_transport(path, queue_size: 0):
            ok(_): return fail("zero queue")
            error(cause):
                try expect_equal(cause, LogError.InvalidInput)

        match async_file_transport(path, max_age: duration(0)):
            ok(_): return fail("zero age")
            error(cause):
                try expect_equal(cause, LogError.InvalidInput)

        match async_file_transport("{directory.path()}/missing/x.ndjson"):
            ok(_): return fail("missing parent")
            error(cause):
                try expect_equal(cause, LogError.FileSystem(FileSystemError.NotFound))

test "a full queue returns LimitExceeded without waiting":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = try value(async_file_transport(path, queue_size: 1)):
            var rejected = false
            var attempts = 0

            while not rejected and attempts < 100000:
                attempts = attempts + 1

                match transport.write("x\n"):
                    ok(_): continue
                    error(cause):
                        cause | try expect_equal(expected: LogError.LimitExceeded)
                        rejected = true

            (not rejected) | try expect_false

test "writes after close are rejected":
    with directory = try value(filesystem().temporary("alog-")):
        let path = "{directory.path()}/events.ndjson"
        let transport = try value(async_file_transport(path))
        transport.close()
        transport.close()

        match transport.write("x\n"):
            ok(_): return fail("write after close")
            error(cause):
                try expect_equal(cause, LogError.Closed)
