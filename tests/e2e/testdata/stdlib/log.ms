import {
    Transport,
    LogLevel,
    LogError,
    create,
    record,
    bind,
    stream_transport,
    stdout_transport,
    file_transport
} from "@std/log.ms"
import {WriteStream, IoError} from "@std/io.ms"
import JsonValue from "@std/json.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import expect_error from "@std/testing.ms"
import MemoryStream from "./support/streams.ms"

type Items:
    items: List[Optional[Int]]

type Payload:
    count: Int
    ok: Bool
    nested: Items
    level: Int
    msg: String
    time: Int

test "logger writes typed escaped records and protects metadata":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = try create(transport, timestamp: false)
        let fields = Payload(
            count: 9007199254740993,
            ok: true,
            nested: Items(items: [none, some(1)]),
            level: 0,
            msg: "fake",
            time: 0
        )
        try record(logger, level: LogLevel.Info, message: "say \"hi\"\nnext", fields)
        let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\}\}\n"
        if output.data.to_string() != some(expected): return panic("typed log record")

        try logger.flush()

    if output.closed: return panic("borrowed stream closed")

test "non-object values are written under data":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = try create(transport, timestamp: false)
        try record(logger, level: LogLevel.Info, message: "n", fields: 7)
        try record(logger, level: LogLevel.Warn, message: "l", fields: ["a", "b"])
        let expected = "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"
        if output.data.to_string() != some(expected): return panic(
            "scalar and list fields"
        )

test "levels filter methods and function values":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = try create(transport, level: LogLevel.Warn, timestamp: false)
        if logger.enabled(LogLevel.Info) or not logger.enabled(LogLevel.Warn): return panic(
            "threshold"
        )

        try logger.trace(message: "filtered")
        try logger.debug(message: "filtered")
        try logger.info(message: "filtered")
        if output.data.length() != 0: return panic("filtered log wrote")

        try logger.warn(message: "warn")
        let error_log = logger.error
        try error_log(message: "error")
        try logger.fatal(message: "fatal")
        logger.set_level(LogLevel.Trace)
        if logger.level() != LogLevel.Trace: return panic("set level")

        try logger.log(level: LogLevel.Trace, message: "trace")
        try logger.debug(message: "debug")
        try logger.info(message: "info")
        let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"
        if output.data.to_string() != some(expected): return panic("level records")

        logger.set_level(LogLevel.Silent)
        if logger.enabled(LogLevel.Fatal) or logger.enabled(LogLevel.Silent): return panic(
            "silent enabled"
        )

        let before = output.data.clone()
        try logger.fatal(message: "filtered")
        if output.data != before: return panic("silent logger wrote")

        let invalid: Result[Unit, LogError] = error(LogError.InvalidInput)
        if logger.log(level: LogLevel.Silent, message: "invalid") != invalid: return panic(
            "silent message level"
        )

type Service:
    service: String

type Request:
    request: Int

test "child bindings snapshot values and merge without mutating inputs":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let root = try create(transport, timestamp: false)
        let logger = try bind(logger: root, bindings: Service(service: "api"))
        let child = try bind(logger, bindings: Request(request: 7))
        logger.set_level(LogLevel.Fatal)
        if child.level() != LogLevel.Info: return panic("child level snapshot")

        try record(
            logger: child,
            level: LogLevel.Info,
            message: "child",
            fields: Service(service: "worker")
        )
        try logger.fatal(message: "parent")
        let expected = "\{\"level\":30,\"msg\":\"child\",\"service\":\"worker\",\"request\":7\}\n\{\"level\":60,\"msg\":\"parent\",\"service\":\"api\"\}\n"
        if output.data.to_string() != some(expected): return panic("binding precedence")

test "limits and unencodable values reject before writing":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
        let logger = try create(
            transport,
            timestamp: false,
            max_bytes: (line.to_bytes().length())
        )
        try logger.info(message: "x")
        if output.data.to_string() != some(line): return panic("exact byte budget")

        let before = output.data.clone()
        let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)
        if logger.info(message: "xx") != limited: return panic("log budget")

        let zero = try create(transport, timestamp: false, max_bytes: 0)
        if zero.info(message: "") != limited: return panic("zero budget")
        if (
            (
                try expect_error(create(transport, max_bytes: -1))
            ) != LogError.InvalidInput
        ): return panic("negative budget")

        let unlimited = try create(transport, timestamp: false)
        let bad = JsonValue.NumberValue("NaN")
        let invalid_data: Result[Unit, LogError] = error(LogError.InvalidData)
        if (
            record(
                logger: unlimited,
                level: LogLevel.Info,
                message: "bad",
                fields: bad
            ) != invalid_data
        ): return panic("invalid JSON")
        if output.data != before: return panic("failed log wrote bytes")

test "transport closure and stream errors preserve identity":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let transport = stream_transport(WriteStream(output))
    let logger = try create(transport)
    output.closed = true
    let io_closed: Result[Unit, LogError] = error(LogError.Io(IoError.Closed))
    if logger.info(message: "closed") != io_closed: return panic("write cause")
    if logger.flush() != io_closed: return panic("flush cause")

    transport.close()
    transport.close()
    let closed: Result[Unit, LogError] = error(LogError.Closed)
    if logger.info(message: "closed") != closed: return panic("transport closed")
    if logger.flush() != closed: return panic("closed flush")

test "file transport appends and flushes with scoped cleanup":
    let fs = filesystem()

    with directory = try fs.temporary("manuscript-log-"):
        let path = "{directory.path()}/events.ndjson"

        with transport = try file_transport(path):
            let logger = try create(transport, timestamp: false)
            try logger.info(message: "first")
            try logger.flush()

        with transport = try file_transport(path):
            let logger = try create(transport, timestamp: false)
            try logger.warn(message: "second")

        let data = try fs.read_file(path)
        if (
            data.to_string() != some(
                "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
            )
        ): return panic("file append")
        if (
            (
                try expect_error(
                    file_transport(
                        "{directory.path()}/missing/events.ndjson"
                    )
                )
            ) != LogError.FileSystem(FileSystemError.NotFound)
        ): return panic("file error cause")

test "stdout transport accepts records and leaves stdout open":
    with transport = stdout_transport():
        let logger = try create(transport, timestamp: false)
        try logger.info(message: "stdout log")
        try logger.flush()

type CaptureTransport:
    output: MemoryStream

impl Transport for CaptureTransport:
    fn write(data: Bytes) Result[Unit, LogError]:
        if self.output.closed: return error(LogError.Closed)

        self.output.data = self.output.data.concat(data)
        return ok(unit)

    fn flush() Result[Unit, LogError]:
        if self.output.closed: return error(LogError.Closed)

        return ok(unit)

    fn close() Unit: self.output.closed = true

test "source transports receive complete records and close through their contract":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let sink = CaptureTransport(output)

    with transport = Transport(sink):
        let logger = try create(transport, timestamp: false)
        try logger.info(message: "source transport")
        try logger.flush()
        if (
            output.data.to_string() != some(
                "\{\"level\":30,\"msg\":\"source transport\"\}\n"
            )
        ): return panic("source transport record")

    if not output.closed: return panic("source transport cleanup")

test "log_json and child_json accept only JSON objects":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = try create(transport, timestamp: false)
        let invalid: Result[Unit, LogError] = error(LogError.InvalidData)

        for text in ["[1]", "5", "null", "\"s\"", "nope"]:
            if (
                logger.log_json(
                    level: LogLevel.Info,
                    message: "m",
                    fields: text
                ) != invalid
            ): return panic("log_json accepted a non-object")
            if logger.child_json(fields: text).is_ok(): return panic(
                "child_json accepted a non-object"
            )

        if output.data.length() != 0: return panic("rejected fields wrote a record")

        try logger.log_json(level: LogLevel.Info, message: "m", fields: "\{\"a\":1\}")
        try record(logger, level: LogLevel.Info, message: "m", fields: [1])
        let expected = "\{\"level\":30,\"msg\":\"m\",\"a\":1\}\n\{\"level\":30,\"msg\":\"m\",\"data\":[1]\}\n"
        if output.data.to_string() != some(expected): return panic(
            "object and wrapped records"
        )
