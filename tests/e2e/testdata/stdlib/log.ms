from "@std/testing.ms" import expect_equal, expect_error, expect_false, expect_ok, expect_true
from "@std/log.ms" import (
    Transport,
    LogLevel,
    LogError,
    create,
    record,
    stream_transport,
    stdout_transport,
    file_transport
)
from "@std/io.ms" import IoError
from "@std/json.ms" import JsonValue
from "@std/fs.ms" import filesystem, FileSystemError
from "@std/bytes.ms" import Bytes

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
def written(path: String) -> Result[Optional[String], Error]:
    let data = try filesystem().read_file(path)
    return ok(data.decode_utf8())

test "logger writes typed escaped records and protects metadata":
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with try create(stream_transport(file.writer()), timestamp: False) as logger:
            let fields = Payload(
                9007199254740993, ok: True, Items([none, some(1)]), 0, "fake", 0
            )
            try record(logger, LogLevel.Info, "say \"hi\"\nnext", fields)

            let expected = "{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"count\":9007199254740993,\"ok\":true,\"nested\":{\"items\":[null,1]}}\n"
            try expect_equal((try written(path)), some(expected))
            try logger.flush()

        (file.append_file("x") | try expect_ok)

test "non-object values are written under data":
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with try create(stream_transport(file.writer()), timestamp: False) as logger:
            try record(logger, LogLevel.Info, "n", 7)
            try record(logger, LogLevel.Warn, "l", ["a", "b"])

            let expected = "{\"level\":30,\"msg\":\"n\",\"data\":7}\n{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]}\n"
            try expect_equal((try written(path)), some(expected))

test "levels filter methods and function values":
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with try create(stream_transport(file.writer()), LogLevel.Warn, False) as logger:
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

            let expected = "{\"level\":40,\"msg\":\"warn\"}\n{\"level\":50,\"msg\":\"error\"}\n{\"level\":60,\"msg\":\"fatal\"}\n{\"level\":10,\"msg\":\"trace\"}\n{\"level\":20,\"msg\":\"debug\"}\n{\"level\":30,\"msg\":\"info\"}\n"
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
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with try create(stream_transport(file.writer()), timestamp: False) as root:
            let logger = try root.child_json("{\"service\":\"api\"}")
            let child = try logger.child_json("{\"request\":7}")
            logger.set_level(LogLevel.Fatal)
            try expect_equal(child.level(), LogLevel.Info)
            try record(child, LogLevel.Info, "child", Service("worker"))
            try logger.fatal("parent")

            let expected = "{\"level\":30,\"msg\":\"child\",\"service\":\"worker\",\"request\":7}\n{\"level\":60,\"msg\":\"parent\",\"service\":\"api\"}\n"
            try expect_equal((try written(path)), some(expected))

test "limits and unencodable values reject before writing":
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)
        let line = "{\"level\":30,\"msg\":\"x\"}\n"

        with try create(
            stream_transport(file.writer()), timestamp: False,
            max_bytes: (line.to_bytes().length())
        ) as logger:
            try logger.info("x")
            try expect_equal((try written(path)), some(line))

            let before = try written(path)
            let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)
            try expect_equal(logger.info("xx"), limited)

            let zero = try create(
                stream_transport(file.writer()), timestamp: False, max_bytes: 0
            )
            try expect_equal(zero.info(""), limited)
            try expect_false(
                (
                    (
                        try expect_error(
                            create(
                                stream_transport(
                                    file.writer()
                                ),
                                max_bytes: -1
                            )
                        )
                    ) != LogError.InvalidInput
                )
            )

            let unlimited = try create(
                stream_transport(file.writer()), timestamp: False
            )
            let bad = JsonValue.NumberValue("NaN")
            let invalid_data: Result[Unit, LogError] = error(LogError.InvalidData)
            try expect_equal(record(unlimited, LogLevel.Info, "bad", bad), invalid_data)
            try expect_equal((try written(path)), before)

test "transport closure and stream errors preserve identity":
    with try filesystem().temporary("manuscript-log-") as directory:
        let file = try filesystem().open(
            path: f"{directory.path()}/out.ndjson", flags: "w", mode: 420
        )
        var logger = try create(stream_transport(file.writer()))
        file.close()

        let io_closed: Result[Unit, LogError] = error(LogError.Io(IoError.Closed))
        try expect_equal(logger.info("closed"), io_closed)
        try expect_equal(logger.flush(), io_closed)
        logger.close()
        logger.close()

        let closed: Result[Unit, LogError] = error(LogError.Closed)
        try expect_equal(logger.info("closed"), closed)
        try expect_equal(logger.flush(), closed)

test "file transport appends and flushes with scoped cleanup":
    let fs = filesystem()

    with try fs.temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/events.ndjson"

        with try create(try file_transport(path), timestamp: False) as logger:
            try logger.info("first")
            try logger.flush()

        with try create(try file_transport(path), timestamp: False) as logger:
            try logger.warn("second")

        let data = try fs.read_file(path)
        try expect_false(
            (
                data.decode_utf8() != some(
                    "{\"level\":30,\"msg\":\"first\"}\n{\"level\":40,\"msg\":\"second\"}\n"
                )
            )
        )
        try expect_false(
            (
                (
                    try expect_error(
                        file_transport(
                            f"{directory.path()}/missing/events.ndjson"
                        )
                    )
                ) != LogError.FileSystem(FileSystemError.NotFound)
            )
        )

test "stdout transport accepts records and leaves stdout open":
    with try create(stdout_transport(), timestamp: False) as logger:
        try logger.info("stdout log")
        try logger.flush()

type CaptureTransport:
    path: String

impl Transport for CaptureTransport:
    def write(data: String) -> Result[Unit, LogError]:
        return self.write_bytes(data.to_bytes())

    def write_bytes(data: Bytes) -> Result[Unit, LogError]:
        if filesystem().read_file(f"{self.path}.closed").is_ok(): return error(
            LogError.Closed
        )

        match filesystem().append_file_bytes(self.path, data):
            case ok(_): return ok(())
            case error(cause): return error(LogError.FileSystem(cause))

    def flush() -> Result[Unit, LogError]:
        if filesystem().read_file(f"{self.path}.closed").is_ok(): return error(
            LogError.Closed
        )

        return ok(())

    def close() -> Unit:
        let marked = filesystem().write_file(f"{self.path}.closed", "closed", True)

test "source transports receive complete records and close through their contract":
    let fs = filesystem()

    with (fs.temporary("manuscript-log-transport-") | try expect_ok) as temporary:
        let path = f"{temporary.path()}/records.ndjson"

        with try create(Transport(CaptureTransport(path.clone())), timestamp: False) as logger:
            try logger.info("source transport")
            try logger.flush()
            try expect_equal(
                (fs.read_file(path) | try expect_ok).decode_utf8(),
                some("{\"level\":30,\"msg\":\"source transport\"}\n")
            )

        try expect_true(fs.read_file(f"{path}.closed").is_ok())

test "log_json and child_json accept only JSON objects":
    with try filesystem().temporary("manuscript-log-") as directory:
        let path = f"{directory.path()}/out.ndjson"
        let file = try filesystem().open(path: path, flags: "w", mode: 420)

        with try create(stream_transport(file.writer()), timestamp: False) as logger:
            let invalid: Result[Unit, LogError] = error(LogError.InvalidData)

            for text in ["[1]", "5", "null", "\"s\"", "nope"]:
                try expect_equal(logger.log_json(LogLevel.Info, "m", text), invalid)
                try expect_false(logger.child_json(text).is_ok())

            try expect_equal((try written(path)), some(""))
            try logger.log_json(LogLevel.Info, "m", "{\"a\":1}")
            try record(logger, LogLevel.Info, "m", [1])

            let expected = "{\"level\":30,\"msg\":\"m\",\"a\":1}\n{\"level\":30,\"msg\":\"m\",\"data\":[1]}\n"
            try expect_equal((try written(path)), some(expected))
