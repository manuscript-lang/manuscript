import {
    Transport,
    LogLevel,
    LogError,
    create,
    stream_transport,
    stdout_transport,
    file_transport
} from "@std/log.ms"
import {WriteStream, IoError} from "@std/io.ms"
import {JsonValue, parse} from "@std/json.ms"
import Map from "@std/collections.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import Optional from "@std/optional.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import MemoryStream from "./support/streams.ms"
import value from "./support/results.ms"

test "logger writes typed escaped records and protects metadata":
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )

    with transport = stream_transport(WriteStream(output)):
        let logger = value(
            create(
                transport: transport,
                timestamp: false
            )
        )
        let fields = value(
            parse(
                text: "\{\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\},\"level\":0,\"msg\":\"fake\",\"time\":0\}"
            )
        )

        match fields:
            ObjectValue(values):
                let written = value(
                    logger.info(
                        message: "say \"hi\"\nnext",
                        fields: values
                    )
                )

            _: return panic("object fields")

        let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\}\}\n"
        if output.data.to_text() != some(expected): return panic(
            "typed log record"
        )

        let flushed = value(logger.flush())

    if output.closed: return panic("borrowed stream closed")

test "levels filter methods and function values":
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )

    with transport = stream_transport(WriteStream(output)):
        let logger = value(
            create(
                transport: transport,
                level: LogLevel.Warn,
                timestamp: false
            )
        )
        if logger.enabled(LogLevel.Info) or not logger.enabled(LogLevel.Warn): return panic(
            "threshold"
        )

        let trace = value(logger.trace(message: "filtered"))
        let debug = value(logger.debug(message: "filtered"))
        let info = value(logger.info(message: "filtered"))
        if output.data.length() != 0: return panic("filtered log wrote")

        let warn = value(logger.warn(message: "warn"))
        let error_log = logger.error
        let failure = value(error_log(message: "error"))
        let fatal = value(logger.fatal(message: "fatal"))
        logger.set_level(LogLevel.Trace)
        if logger.level() != LogLevel.Trace: return panic("set level")

        let traced = value(logger.log(level: LogLevel.Trace, message: "trace"))
        let debugged = value(logger.debug(message: "debug"))
        let informed = value(logger.info(message: "info"))
        let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"
        if output.data.to_text() != some(expected): return panic("level records")

        logger.set_level(LogLevel.Silent)
        if logger.enabled(LogLevel.Fatal) or logger.enabled(LogLevel.Silent): return panic(
            "silent enabled"
        )

        let before = output.data.clone()
        let silent = value(logger.fatal(message: "filtered"))
        if output.data != before: return panic("silent logger wrote")

        let invalid: Result[Unit, LogError] = error(LogError.InvalidInput)
        if logger.log(level: LogLevel.Silent, message: "invalid") != invalid: return panic(
            "silent message level"
        )

test "child bindings snapshot membership and merge without mutating inputs":
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )

    with transport = stream_transport(WriteStream(output)):
        let bindings = Map[String, JsonValue]().add(
            key: "service",
            value: JsonValue.StringValue("api")
        )
        let logger = value(
            create(
                transport: transport,
                bindings: bindings,
                timestamp: false
            )
        )
        bindings.add(
            key: "service",
            value: JsonValue.StringValue("changed")
        )
        let child_fields = Map[String, JsonValue]().add(
            key: "request",
            value: JsonValue.NumberValue("7")
        )
        let child = logger.child(child_fields)
        child_fields.add(
            key: "request",
            value: JsonValue.NumberValue("9")
        )
        logger.set_level(LogLevel.Fatal)
        if child.level() != LogLevel.Info: return panic("child level snapshot")

        let fields = Map[String, JsonValue]().add(
            key: "service",
            value: JsonValue.StringValue("worker")
        )
        let child_log = value(
            child.info(
                message: "child",
                fields: fields
            )
        )
        let parent_log = value(logger.fatal(message: "parent"))
        let expected = "\{\"level\":30,\"msg\":\"child\",\"service\":\"worker\",\"request\":7\}\n\{\"level\":60,\"msg\":\"parent\",\"service\":\"api\"\}\n"
        if output.data.to_text() != some(expected): return panic(
            "binding precedence"
        )
        if fields.length() != 1: return panic("log mutated fields")

test "limits and invalid JSON reject before writing":
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )

    with transport = stream_transport(WriteStream(output)):
        let record = "\{\"level\":30,\"msg\":\"x\"\}\n"
        let logger = value(
            create(
                transport: transport,
                timestamp: false,
                max_bytes: (record.to_bytes().length())
            )
        )
        let written = value(logger.info(message: "x"))
        if output.data.to_text() != some(record): return panic(
            "exact byte budget"
        )

        let before = output.data.clone()
        let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)
        if logger.info(message: "xx") != limited: return panic("log budget")

        let zero = value(
            create(
                transport: transport,
                timestamp: false,
                max_bytes: 0
            )
        )
        if zero.info(message: "") != limited: return panic("zero budget")

        match create(
            transport: transport,
            max_bytes: -1
        ):
            ok(_): return panic("negative budget accepted")

            error(cause):
                if cause != LogError.InvalidInput: return panic("negative budget")

        let unlimited = value(
            create(
                transport: transport,
                timestamp: false
            )
        )
        let bad = Map[String, JsonValue]().add(
            key: "n",
            value: JsonValue.NumberValue("NaN")
        )
        let invalid_data: Result[Unit, LogError] = error(LogError.InvalidData)
        if unlimited.info(
            message: "bad",
            fields: bad
        ) != invalid_data: return panic("invalid JSON")
        if output.data != before: return panic("failed log wrote bytes")

test "transport closure and stream errors preserve identity":
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )
    let transport = stream_transport(WriteStream(output))
    let logger = value(create(transport: transport))
    output.closed = true
    let io_closed: Result[Unit, LogError] = error(
        LogError.Io(IoError.Closed)
    )
    if logger.info(message: "closed") != io_closed: return panic("write cause")
    if logger.flush() != io_closed: return panic("flush cause")

    transport.close()
    transport.close()
    let closed: Result[Unit, LogError] = error(LogError.Closed)
    if logger.info(message: "closed") != closed: return panic("transport closed")
    if logger.flush() != closed: return panic("closed flush")

test "file transport appends and flushes with scoped cleanup":
    let fs = filesystem()

    with directory = value(fs.temporary("manuscript-log-")):
        let path = "{directory.path()}/events.ndjson"

        with transport = value(file_transport(path)):
            let logger = value(
                create(
                    transport: transport,
                    timestamp: false
                )
            )
            let written = value(logger.info(message: "first"))
            let flushed = value(logger.flush())

        with transport = value(file_transport(path)):
            let logger = value(
                create(
                    transport: transport,
                    timestamp: false
                )
            )
            let written = value(logger.warn(message: "second"))

        let data = value(fs.read_file(path: path))
        if (
            data.to_text() != some(
                "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
            )
        ): return panic("file append")

        match file_transport("{directory.path()}/missing/events.ndjson"):
            ok(_): return panic("missing parent accepted")

            error(cause):
                if cause != LogError.FileSystem(FileSystemError.NotFound): return panic(
                    "file error cause"
                )

test "stdout transport accepts records and leaves stdout open":
    with transport = stdout_transport():
        let logger = value(
            create(
                transport: transport,
                timestamp: false
            )
        )
        let written = value(logger.info(message: "stdout log"))
        let flushed = value(logger.flush())

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
    let output = MemoryStream(
        data: "".to_bytes(),
        offset: 0,
        closed: false
    )
    let sink = CaptureTransport(output)

    with transport = Transport(sink):
        let logger = value(
            create(
                transport: transport,
                timestamp: false
            )
        )
        let written = value(logger.info(message: "source transport"))
        let flushed = value(logger.flush())
        if (
            output.data.to_text() != some(
                "\{\"level\":30,\"msg\":\"source transport\"\}\n"
            )
        ): return panic("source transport record")

    if not output.closed: return panic("source transport cleanup")
