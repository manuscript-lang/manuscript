import (
    expect_equal,
    expect_error,
    expect_false,
    expect_ok,
    expect_true
) from "@std/test/test.ms"
import (
    Logger,
    Transport,
    LogLevel,
    LogError,
    create,
    stream_transport,
    stdout_transport,
    file_transport
) from "@std/log.ms"
import IoError, WriteStream from "@std/io/io.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import JsonValue, parse from "@std/data/json.ms"
import (
    FileSystemError,
    append_file_bytes,
    open,
    read_file,
    temporary,
    write_file
) from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

type Items:
    items: List[Int?]

type Payload:
    count: Int
    ok: Bool
    nested: Items
    level: Int
    msg: String
    time: Int

# The text a test's file sink received so far.
fn written(path: String) String?!:
    let data = try read_file(path)
    return ok(data.decode_utf8())

test "logger writes typed escaped records and protects metadata":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    var logger = try create(stream_transport(file.writer()), timestamp: false)
    let fields = Payload(9007199254740993, ok: true, Items([none, 1]), 0, "fake", 0)
    try logger.info("say \"hi\"\nnext", fields)

    let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"data\":\{\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\},\"level\":0,\"msg\":\"fake\",\"time\":0\}\}\n"
    try expect_equal((try written(path)), expected)
    try logger.flush()
    logger.close()
    file.append_file("x") | try expect_ok

test "non-object values are written under data":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let logger = try create(stream_transport(file.writer()), timestamp: false)
    try logger.info("n", 7)
    try logger.warn("l", ["a", "b"])

    let expected = "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"
    try expect_equal((try written(path)), expected)

test "levels filter methods and function values":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    var logger = try create(stream_transport(file.writer()), LogLevel.Warn, false)
    try expect_false(
        (logger.enabled(LogLevel.Info) or not logger.enabled(LogLevel.Warn))
    )
    try logger.trace("filtered")
    try logger.debug("filtered")
    try logger.info("filtered")
    try expect_equal((try written(path)), "")
    try logger.warn("warn")

    let error_log = fn(message: String) Unit!LogError: logger.error(message)
    try error_log("error")
    try logger.fatal("fatal")
    logger.set_level(LogLevel.Trace)
    try expect_equal(logger.level(), LogLevel.Trace)
    try logger.log(LogLevel.Trace, "trace")
    try logger.debug("debug")
    try logger.info("info")

    let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"
    try expect_equal((try written(path)), expected)
    logger.set_level(LogLevel.Silent)
    try expect_false(
        (logger.enabled(LogLevel.Fatal) or logger.enabled(LogLevel.Silent))
    )

    let before = try written(path)
    try logger.fatal("filtered")
    try expect_equal((try written(path)), before)

    let invalid: Unit!LogError = error(LogError.InvalidInput)
    try expect_equal(logger.log(LogLevel.Silent, "invalid"), invalid)

type Service:
    service: String

type Request:
    request: Int

test "child bindings snapshot values and merge without mutating inputs":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let root = try create(stream_transport(file.writer()), timestamp: false)
    var logger = try root.child(Service("api"))
    let child = try logger.child(Request(7))
    logger.set_level(LogLevel.Fatal)
    try expect_equal(child.level(), LogLevel.Info)
    try child.info("child", Service("worker"))
    try logger.fatal("parent")

    let expected = "\{\"level\":30,\"msg\":\"child\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"service\":\"worker\"\}\}\n\{\"level\":60,\"msg\":\"parent\",\"context\":\{\"service\":\"api\"\}\}\n"
    try expect_equal((try written(path)), expected)

test "limits and unencodable values reject before writing":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
    let logger = try create(
        stream_transport(file.writer()), timestamp: false,
        max_bytes: (line.to_bytes().length())
    )
    try logger.info("x")
    try expect_equal((try written(path)), line)

    let before = try written(path)
    let limited: Unit!LogError = error(LogError.LimitExceeded)
    try expect_equal(logger.info("xx"), limited)

    let zero = try create(
        stream_transport(file.writer()), timestamp: false, max_bytes: 0
    )
    try expect_equal(zero.info(""), limited)
    try expect_false(
        (
            (
                try expect_error(
                    create(
                        stream_transport(file.writer()), max_bytes: -1
                    )
                )
            ) != LogError.InvalidInput
        )
    )

    let unlimited = try create(stream_transport(file.writer()), timestamp: false)
    let bad = JsonValue.NumberValue("NaN")
    let invalid_data: Unit!LogError = error(LogError.InvalidData)
    try expect_equal(unlimited.info("bad", bad), invalid_data)
    try expect_equal((try written(path)), before)

test "transport closure and stream errors preserve identity":
    let directory = try temporary("manuscript-log-")
    var file = try open(path: "{directory.path()}/out.ndjson", flags: "w", mode: 420)
    var logger = try create(stream_transport(file.writer()))
    try file.close()

    let io_closed: Unit!LogError = error(LogError.Io(IoError.Closed))
    try expect_equal(logger.info("closed"), io_closed)
    try expect_equal(logger.flush(), io_closed)
    logger.close()
    logger.close()

    let closed: Unit!LogError = error(LogError.Closed)
    try expect_equal(logger.info("closed"), closed)
    try expect_equal(logger.flush(), closed)

test "file transport appends and flushes with scoped cleanup":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    var logger = try create(try file_transport(path), timestamp: false)
    try logger.info("first")
    try logger.flush()
    logger.close()

    var logger2 = try create(try file_transport(path), timestamp: false)
    try logger2.warn("second")
    logger2.close()

    let data = try read_file(path)
    try expect_false(
        (
            data.decode_utf8() != "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
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
    let logger = try create(stdout_transport(), timestamp: false)
    try logger.info("stdout log")
    try logger.flush()

type CaptureTransport:
    path: String

impl Transport for CaptureTransport:
    fn write(data: String) Unit!LogError:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Unit!LogError:
        if read_file("{self.path}.closed").is_ok(): return error(LogError.Closed)

        match append_file_bytes(self.path, data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.FileSystem(cause))

    fn flush() Unit!LogError:
        if read_file("{self.path}.closed").is_ok(): return error(LogError.Closed)

        return ok(unit)

    fn close() Unit:
        let _marked = write_file("{self.path}.closed", "closed", true)

test "source transports receive complete records and close through their contract":
    let temporary = temporary("manuscript-log-transport-") | try expect_ok
    let path = "{temporary.path()}/records.ndjson"
    var logger = try create(CaptureTransport(path.clone()), timestamp: false)
    try logger.info("source transport")
    try logger.flush()
    try expect_equal(
        (read_file(path) | try expect_ok).decode_utf8(),
        "\{\"level\":30,\"msg\":\"source transport\"\}\n"
    )
    logger.close()
    try expect_true(read_file("{path}.closed").is_ok())

test "unencodable fields are rejected and fields keep their shape under data":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let logger = try create(stream_transport(file.writer()), timestamp: false)
    let invalid: Unit!LogError = error(LogError.InvalidData)
    let nan = JsonValue.NumberValue("NaN")
    try expect_equal(logger.info("m", nan), invalid)
    try expect_false(logger.child(nan).is_ok())
    try expect_equal((try written(path)), "")
    try logger.log(LogLevel.Info, "m", Service("a"))
    try logger.info("m", [1])

    let expected = "\{\"level\":30,\"msg\":\"m\",\"data\":\{\"service\":\"a\"\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":[1]\}\n"
    try expect_equal((try written(path)), expected)

# A stream that suspends in the middle of a write, so only the transport keeps records whole.
type SlowStream:
    parts: Shared[List[String]]

impl WriteStream for SlowStream:
    var fn close() Unit:
        return unit

    var fn flush() Unit!IoError:
        return ok(unit)

    var fn write(data: String) Unit!IoError:
        let half = data.length() / 2
        var first = lock(self.parts)
        first.value.append(data.slice(0, half).get(""))
        first.close().get(none)
        sleep(nanoseconds(1000000))

        var second = lock(self.parts)
        second.value.append(data.slice(half, data.length()).get(""))
        second.close().get(none)
        return ok(unit)

    var fn write_bytes(data: Bytes) Unit!IoError:
        return self.write(data.decode_utf8().get(""))

fn chatter(logger: Logger, name: String) Unit!:
    for n in 0..3:
        try logger.info("m", name)
    return ok(unit)

test "concurrent tasks never interleave a record":
    let parts = share(List[String]())
    let logger = (create(stream_transport(SlowStream(parts)), timestamp: false)).get()
    let group = TaskGroup[Unit!, Unit, Unit]()
    let first = logger.clone()
    let second = logger.clone()
    let a = group.spawn(fn ch: chatter(first, "a"))
    let b = group.spawn(fn ch: chatter(second, "b"))
    a.result() | try expect_ok | try expect_ok
    b.result() | try expect_ok | try expect_ok

    var guard = lock(parts)
    let text = guard.value.join("")
    try expect_equal(text.split("\n").length(), 7)
    for line in text.split("\n"):
        if line != "":
            try expect_equal(
                line == "\{\"level\":30,\"msg\":\"m\",\"data\":\"a\"\}"
                or line == "\{\"level\":30,\"msg\":\"m\",\"data\":\"b\"\}",
                true
            )

# A transport that keeps every record in memory.
type Memory:
    out: Shared[List[String]]

impl Transport for Memory:
    fn write(data: String) Unit!LogError:
        var guard = lock(self.out)
        guard.value.append(data.clone())
        return ok(unit)

    fn write_bytes(data: Bytes) Unit!LogError:
        return self.write(data.decode_utf8().get(""))

    fn flush() Unit!LogError:
        return ok(unit)

    fn close() Unit:
        return unit

fn recorded(out: Shared[List[String]]) String:
    var guard = lock(out)
    return guard.value.join("")

test "messages are escaped and fields keep their shape under data":
    let out = share(List[String]())
    let logger = try create(Memory(out), timestamp: false)
    try logger.info("a<b>&\"\n\t\u{1}é")
    try logger.info("m", Items([none, 1]))
    try logger.info("m", "text")
    try logger.info("m", JsonValue.Null)
    try logger.info("m", JsonValue.ObjectValue(Map[String, JsonValue]()))

    let expected = "\{\"level\":30,\"msg\":\"a<b>&\\\"\\n\\t\\u0001é\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\"items\":[null,1]\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\"text\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":null\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\}\}\n"
    try expect_equal(recorded(out), expected)

test "child context merges per child and the newer value wins":
    let out = share(List[String]())
    let root = try create(Memory(out), timestamp: false)
    let api = try root.child(Service("api"))
    let both = try api.child(Request(7))
    let renamed = try both.child(Service("worker"))
    let replaced = try both.child(3)
    try root.info("root")
    try api.info("api")
    try both.info("both", Request(9))
    try renamed.info("renamed")
    try replaced.info("replaced")

    let expected = "\{\"level\":30,\"msg\":\"root\"\}\n\{\"level\":30,\"msg\":\"api\",\"context\":\{\"service\":\"api\"\}\}\n\{\"level\":30,\"msg\":\"both\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"request\":9\}\}\n\{\"level\":30,\"msg\":\"renamed\",\"context\":\{\"service\":\"worker\",\"request\":7\}\}\n\{\"level\":30,\"msg\":\"replaced\",\"context\":3\}\n"
    try expect_equal(recorded(out), expected)

test "the time field is a millisecond count and the size limit counts the newline":
    let out = share(List[String]())
    let stamped = try create(Memory(out))
    try stamped.info("t")

    let line = recorded(out)
    try expect_true(line.starts_with("\{\"level\":30,\"msg\":\"t\",\"time\":1"))

    let quiet = share(List[String]())
    let plain = "\{\"level\":30,\"msg\":\"ab\"\}\n"
    let exact = try create(
        Memory(quiet), timestamp: false, max_bytes: plain.to_bytes().length()
    )
    try exact.info("ab")
    try expect_equal(recorded(quiet), plain)

    let tight = try create(
        Memory(quiet), timestamp: false, max_bytes: plain.to_bytes().length() - 1
    )
    let limited: Unit!LogError = error(LogError.LimitExceeded)
    try expect_equal(tight.info("ab"), limited)
    try expect_equal(recorded(quiet), plain)
