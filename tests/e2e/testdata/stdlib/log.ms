import {expect_equal, expect_error, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {
    Transport, LogLevel, LogError, create, record, bind, stream_transport,
    stdout_transport, file_transport
} from "@std/log.ms"
import IoError from "@std/io.ms"
import JsonValue from "@std/json.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"

type Items:
    items: List[Optional[Int]]

type Payload:
    count: Int
    ok: Bool
    nested: Items
    level: Int
    msg: String
    time: Int

# The text a test's file sink received so far.
fn written(path: String) Result[Optional[String], Error]:
    let data = try filesystem().read_file(path)

    return ok(data.decode_utf8())

test "logger writes typed escaped records and protects metadata":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let logger = try create(transport, timestamp: false)
            let fields = Payload(
                9007199254740993, ok: true, Items([none, some(1)]), 0, "fake", 0
            )

            try record(logger, LogLevel.Info, "say \"hi\"\nnext", fields)

            let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\}\}\n"

            try expect_equal((try written(path)), some(expected))
            try logger.flush()

        (file.append_file("x") | try expect_ok)

test "non-object values are written under data":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let logger = try create(transport, timestamp: false)

            try record(logger, LogLevel.Info, "n", 7)
            try record(logger, LogLevel.Warn, "l", ["a", "b"])

            let expected = "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"

            try expect_equal((try written(path)), some(expected))

test "levels filter methods and function values":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let logger = try create(transport, LogLevel.Warn, false)

            try expect_false(
                (
                    logger.enabled(LogLevel.Info)
                    or not logger.enabled(LogLevel.Warn)
                )
            )
            try logger.trace("filtered")
            try logger.debug("filtered")
            try logger.info("filtered")
            try expect_equal((try written(path)), some(""))
            try logger.warn("warn")

            let error_log = logger.error

            try error_log("error")
            try logger.fatal("fatal")
            logger.set_level(LogLevel.Trace)
            try expect_equal(logger.level(), LogLevel.Trace)
            try logger.log(LogLevel.Trace, "trace")
            try logger.debug("debug")
            try logger.info("info")

            let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"

            try expect_equal((try written(path)), some(expected))
            logger.set_level(LogLevel.Silent)
            try expect_false(
                (
                    logger.enabled(LogLevel.Fatal)
                    or logger.enabled(LogLevel.Silent)
                )
            )

            let before = try written(path)

            try logger.fatal("filtered")
            try expect_equal((try written(path)), before)

            let invalid: Result[Unit, LogError] = error(LogError.InvalidInput)

            try expect_equal(logger.log(LogLevel.Silent, "invalid"), invalid)

type Service:
    service: String

type Request:
    request: Int

test "child bindings snapshot values and merge without mutating inputs":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let root = try create(transport, timestamp: false)
            let logger = try bind(root, Service("api"))
            let child = try bind(logger, Request(7))

            logger.set_level(LogLevel.Fatal)
            try expect_equal(child.level(), LogLevel.Info)
            try record(child, LogLevel.Info, "child", Service("worker"))
            try logger.fatal("parent")

            let expected = "\{\"level\":30,\"msg\":\"child\",\"service\":\"worker\",\"request\":7\}\n\{\"level\":60,\"msg\":\"parent\",\"service\":\"api\"\}\n"

            try expect_equal((try written(path)), some(expected))

test "limits and unencodable values reject before writing":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
            let logger = try create(
                transport, timestamp: false, max_bytes: (line.to_bytes().length())
            )

            try logger.info("x")
            try expect_equal((try written(path)), some(line))

            let before = try written(path)
            let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)

            try expect_equal(logger.info("xx"), limited)

            let zero = try create(transport, timestamp: false, max_bytes: 0)

            try expect_equal(zero.info(""), limited)
            try expect_false(
                (
                    (
                        try expect_error(
                            create(transport, max_bytes: -1)
                        )
                    ) != LogError.InvalidInput
                )
            )

            let unlimited = try create(transport, timestamp: false)
            let bad = JsonValue.NumberValue("NaN")
            let invalid_data: Result[Unit, LogError] = error(LogError.InvalidData)

            try expect_equal(record(unlimited, LogLevel.Info, "bad", bad), invalid_data)
            try expect_equal((try written(path)), before)

test "transport closure and stream errors preserve identity":
    with directory = try filesystem().temporary("manuscript-log-"):
        let file = try filesystem().open(
            path: "{directory.path()}/out.ndjson", flags: "w", mode: 420
        )
        let transport = stream_transport(file.writer())
        let logger = try create(transport)

        file.close()

        let io_closed: Result[Unit, LogError] = error(LogError.Io(IoError.Closed))

        try expect_equal(logger.info("closed"), io_closed)
        try expect_equal(logger.flush(), io_closed)
        transport.close()
        transport.close()

        let closed: Result[Unit, LogError] = error(LogError.Closed)

        try expect_equal(logger.info("closed"), closed)
        try expect_equal(logger.flush(), closed)

test "file transport appends and flushes with scoped cleanup":
    let fs = filesystem()

    with directory = try fs.temporary("manuscript-log-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try file_transport(path):
            let logger = try create(transport, timestamp: false)

            try logger.info("first")
            try logger.flush()

        with transport = try file_transport(path):
            let logger = try create(transport, timestamp: false)

            try logger.warn("second")

        let data = try fs.read_file(path)

        try expect_false(
            (
                data.decode_utf8() != some(
                    "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
                )
            )
        )
        try expect_false(
            (
                (
                    try expect_error(
                        file_transport(
                            "{directory.path()}/missing/events.ndjson"
                        )
                    )
                ) != LogError.FileSystem(FileSystemError.NotFound)
            )
        )

test "stdout transport accepts records and leaves stdout open":
    with transport = stdout_transport():
        let logger = try create(transport, timestamp: false)

        try logger.info("stdout log")
        try logger.flush()

type CaptureTransport:
    path: String

impl Transport for CaptureTransport:
    fn write(data: String) Result[Unit, LogError]:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Result[Unit, LogError]:
        if filesystem().read_file("{self.path}.closed").is_ok(): return error(
            LogError.Closed
        )

        match filesystem().append_file_bytes(self.path, data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.FileSystem(cause))

    fn flush() Result[Unit, LogError]:
        if filesystem().read_file("{self.path}.closed").is_ok(): return error(
            LogError.Closed
        )

        return ok(unit)

    fn close() Unit:
        let marked = filesystem().write_file("{self.path}.closed", "closed", true)

test "source transports receive complete records and close through their contract":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-log-transport-") | try expect_ok):
        let path = "{temporary.path()}/records.ndjson"

        with transport = Transport(CaptureTransport(path.clone())):
            let logger = try create(transport, timestamp: false)

            try logger.info("source transport")
            try logger.flush()
            try expect_equal(
                (fs.read_file(path) | try expect_ok).decode_utf8(),
                some("\{\"level\":30,\"msg\":\"source transport\"\}\n")
            )

        try expect_true(fs.read_file("{path}.closed").is_ok())

test "log_json and child_json accept only JSON objects":
    with directory = try filesystem().temporary("manuscript-log-"):
        let path = "{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with transport = stream_transport(file.writer()):
            let logger = try create(transport, timestamp: false)
            let invalid: Result[Unit, LogError] = error(LogError.InvalidData)

            for text in ["[1]", "5", "null", "\"s\"", "nope"]:
                try expect_equal(logger.log_json(LogLevel.Info, "m", text), invalid)
                try expect_false(logger.child_json(text).is_ok())

            try expect_equal((try written(path)), some(""))
            try logger.log_json(LogLevel.Info, "m", "\{\"a\":1\}")
            try record(logger, LogLevel.Info, "m", [1])

            let expected = "\{\"level\":30,\"msg\":\"m\",\"a\":1\}\n\{\"level\":30,\"msg\":\"m\",\"data\":[1]\}\n"

            try expect_equal((try written(path)), some(expected))
