import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
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
        let logger = (create(transport: transport, timestamp: false) | try expect_ok)
        let fields = Payload(
            count: 9007199254740993,
            ok: true,
            nested: Items(items: [none, some(1)]),
            level: 0,
            msg: "fake",
            time: 0
        )
        let written = (
            record(
                logger: logger,
                level: LogLevel.Info,
                message: "say \"hi\"\nnext",
                fields: fields
            ) | try expect_ok
        )
        let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\}\}\n"
        output.data.to_string() | try expect_equal(expected: some(expected))
        let flushed = (logger.flush() | try expect_ok)

    output.closed | try expect_false

test "non-object values are written under data":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = (create(transport: transport, timestamp: false) | try expect_ok)
        let counted = (
            record(
                logger: logger,
                level: LogLevel.Info,
                message: "n",
                fields: 7
            ) | try expect_ok
        )
        let listed = (
            record(
                logger: logger,
                level: LogLevel.Warn,
                message: "l",
                fields: ["a", "b"]
            ) | try expect_ok
        )
        let expected = "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"
        output.data.to_string() | try expect_equal(expected: some(expected))

test "levels filter methods and function values":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let logger = (
            create(
                transport: transport,
                level: LogLevel.Warn,
                timestamp: false
            ) | try expect_ok
        )
        try expect_false(
            (
                logger.enabled(LogLevel.Info)
                or not logger.enabled(LogLevel.Warn)
            )
        )
        let trace = (logger.trace(message: "filtered") | try expect_ok)
        let debug = (logger.debug(message: "filtered") | try expect_ok)
        let info = (logger.info(message: "filtered") | try expect_ok)
        output.data.length() | try expect_equal(expected: 0)
        let warn = (logger.warn(message: "warn") | try expect_ok)
        let error_log = logger.error
        let failure = (error_log(message: "error") | try expect_ok)
        let fatal = (logger.fatal(message: "fatal") | try expect_ok)
        logger.set_level(LogLevel.Trace)
        logger.level() | try expect_equal(expected: LogLevel.Trace)
        let traced = (
            logger.log(
                level: LogLevel.Trace,
                message: "trace"
            ) | try expect_ok
        )
        let debugged = (logger.debug(message: "debug") | try expect_ok)
        let informed = (logger.info(message: "info") | try expect_ok)
        let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"
        output.data.to_string() | try expect_equal(expected: some(expected))
        logger.set_level(LogLevel.Silent)
        try expect_false(
            (
                logger.enabled(LogLevel.Fatal)
                or logger.enabled(LogLevel.Silent)
            )
        )
        let before = output.data.clone()
        let silent = (logger.fatal(message: "filtered") | try expect_ok)
        output.data | try expect_equal(expected: before)
        let invalid: Result[Unit, LogError] = error(LogError.InvalidInput)
        logger.log(level: LogLevel.Silent, message: "invalid") | try expect_equal(
            expected: invalid
        )

type Service:
    service: String

type Request:
    request: Int

test "child bindings snapshot values and merge without mutating inputs":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let root = (create(transport: transport, timestamp: false) | try expect_ok)
        let logger = (
            bind(
                logger: root,
                bindings: Service(service: "api")
            ) | try expect_ok
        )
        let child = (
            bind(
                logger: logger,
                bindings: Request(request: 7)
            ) | try expect_ok
        )
        logger.set_level(LogLevel.Fatal)
        child.level() | try expect_equal(expected: LogLevel.Info)
        let child_log = (
            record(
                logger: child,
                level: LogLevel.Info,
                message: "child",
                fields: Service(service: "worker")
            ) | try expect_ok
        )
        let parent_log = (logger.fatal(message: "parent") | try expect_ok)
        let expected = "\{\"level\":30,\"msg\":\"child\",\"service\":\"worker\",\"request\":7\}\n\{\"level\":60,\"msg\":\"parent\",\"service\":\"api\"\}\n"
        output.data.to_string() | try expect_equal(expected: some(expected))

test "limits and unencodable values reject before writing":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)

    with transport = stream_transport(WriteStream(output)):
        let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
        let logger = (
            create(
                transport: transport,
                timestamp: false,
                max_bytes: (line.to_bytes().length())
            ) | try expect_ok
        )
        let written = (logger.info(message: "x") | try expect_ok)
        output.data.to_string() | try expect_equal(expected: some(line))
        let before = output.data.clone()
        let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)
        logger.info(message: "xx") | try expect_equal(expected: limited)
        let zero = (
            create(
                transport: transport,
                timestamp: false,
                max_bytes: 0
            ) | try expect_ok
        )
        zero.info(message: "") | try expect_equal(expected: limited)

        match create(transport: transport, max_bytes: -1):
            ok(_): return fail("negative budget accepted")
            error(cause):
                try expect_equal(cause, LogError.InvalidInput)

        let unlimited = (create(transport: transport, timestamp: false) | try expect_ok)
        let bad = JsonValue.NumberValue("NaN")
        let invalid_data: Result[Unit, LogError] = error(LogError.InvalidData)
        try expect_false(
            (
                record(
                    logger: unlimited,
                    level: LogLevel.Info,
                    message: "bad",
                    fields: bad
                ) != invalid_data
            )
        )
        output.data | try expect_equal(expected: before)

test "transport closure and stream errors preserve identity":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let transport = stream_transport(WriteStream(output))
    let logger = (create(transport: transport) | try expect_ok)
    output.closed = true
    let io_closed: Result[Unit, LogError] = error(LogError.Io(IoError.Closed))
    logger.info(message: "closed") | try expect_equal(expected: io_closed)
    logger.flush() | try expect_equal(expected: io_closed)
    transport.close()
    transport.close()
    let closed: Result[Unit, LogError] = error(LogError.Closed)
    logger.info(message: "closed") | try expect_equal(expected: closed)
    logger.flush() | try expect_equal(expected: closed)

test "file transport appends and flushes with scoped cleanup":
    let fs = filesystem()

    with directory = (fs.temporary("manuscript-log-") | try expect_ok):
        let path = "{directory.path()}/events.ndjson"

        with transport = (file_transport(path) | try expect_ok):
            let logger = (
                create(
                    transport: transport,
                    timestamp: false
                ) | try expect_ok
            )
            let written = (logger.info(message: "first") | try expect_ok)
            let flushed = (logger.flush() | try expect_ok)

        with transport = (file_transport(path) | try expect_ok):
            let logger = (
                create(
                    transport: transport,
                    timestamp: false
                ) | try expect_ok
            )
            let written = (logger.warn(message: "second") | try expect_ok)

        let data = (fs.read_file(path: path) | try expect_ok)
        try expect_false(
            (
                data.to_string() != some(
                    "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
                )
            )
        )

        match file_transport("{directory.path()}/missing/events.ndjson"):
            ok(_): return fail("missing parent accepted")
            error(cause):
                try expect_equal(cause, LogError.FileSystem(FileSystemError.NotFound))

test "stdout transport accepts records and leaves stdout open":
    with transport = stdout_transport():
        let logger = (create(transport: transport, timestamp: false) | try expect_ok)
        let written = (logger.info(message: "stdout log") | try expect_ok)
        let flushed = (logger.flush() | try expect_ok)

type CaptureTransport:
    output: MemoryStream

impl Transport for CaptureTransport:
    fn write(data: Bytes) -> Result[Unit, LogError]:
        if self.output.closed: return error(LogError.Closed)

        self.output.data = self.output.data.concat(data)
        return ok(unit)

    fn flush() -> Result[Unit, LogError]:
        if self.output.closed: return error(LogError.Closed)

        return ok(unit)

    fn close() -> Unit: self.output.closed = true

test "source transports receive complete records and close through their contract":
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let sink = CaptureTransport(output)

    with transport = Transport(sink):
        let logger = (create(transport: transport, timestamp: false) | try expect_ok)
        let written = (logger.info(message: "source transport") | try expect_ok)
        let flushed = (logger.flush() | try expect_ok)
        try expect_false(
            (
                output.data.to_string() != some(
                    "\{\"level\":30,\"msg\":\"source transport\"\}\n"
                )
            )
        )

    (output.closed) | try expect_true
