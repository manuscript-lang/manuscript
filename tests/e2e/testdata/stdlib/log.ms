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
    create,
    handle_transport,
    stdout_transport,
    file_transport,
    rotating_file_transport
) from "@std/log.ms"
import promise from "@std/concurrency/promise.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import JsonValue, parse from "@std/data/json.ms"
import (
    append_file,
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

// The text a test's file sink received so far.
fn written(path: String) String?!:
    let data = try read_file(path)
    return ok(data.decode_utf8())

test "logger writes typed escaped records and protects metadata":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    var logger = try create(try file_transport(path.clone()), timestamp: false)
    let fields = Payload(9007199254740993, ok: true, Items([none, 1]), 0, "fake", 0)
    try logger.info("say \"hi\"\nnext", fields)

    let expected = "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"data\":\{\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\},\"level\":0,\"msg\":\"fake\",\"time\":0\}\}\n"
    try expect_equal((try written(path)), expected)
    try logger.flush()
    try logger.close()
    try expect_true(logger.info("late").is_error())

test "non-object values are written under data":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let logger = try create(handle_transport(file), timestamp: false)
    try logger.info("n", 7)
    try logger.warn("l", ["a", "b"])

    let expected = "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"
    try expect_equal((try written(path)), expected)

test "levels filter methods and function values":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    var logger = try create(handle_transport(file), LogLevel.Warn, false)
    try expect_false(
        (logger.enabled(LogLevel.Info) or not logger.enabled(LogLevel.Warn))
    )
    try logger.trace("filtered")
    try logger.debug("filtered")
    try logger.info("filtered")
    try expect_equal((try written(path)), "")
    try logger.warn("warn")

    let error_log = logger.error[Unit]
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

    let invalid: Unit! = error(
        Error("logging: invalid input", kind: ErrorCategory.InvalidInput)
    )
    try expect_equal(logger.log(LogLevel.Silent, "invalid"), invalid)

type Service:
    service: String

type Request:
    request: Int

test "child bindings snapshot values and merge without mutating inputs":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let root = try create(handle_transport(file), timestamp: false)
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
    let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
    let logger = try create(
        try file_transport(path.clone()), timestamp: false,
        max_bytes: (line.to_bytes().length())
    )
    try logger.info("x")
    try expect_equal((try written(path)), line)

    let before = try written(path)
    let limited: Unit! = error(
        Error("logging: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    try expect_equal(logger.info("xx"), limited)

    let zero = try create(
        try file_transport(path.clone()), timestamp: false, max_bytes: 0
    )
    try expect_equal(zero.info(""), limited)
    try expect_false(
        (
            (
                try expect_error(
                    create(
                        try file_transport(path.clone()), max_bytes: -1
                    )
                )
            ) != Error("logging: invalid input", kind: ErrorCategory.InvalidInput)
        )
    )

    let unlimited = try create(try file_transport(path.clone()), timestamp: false)
    let bad = JsonValue.NumberValue("NaN")
    let invalid_data: Unit! = error(
        Error("logging: invalid data", kind: ErrorCategory.InvalidData)
    )
    try expect_equal(unlimited.info("bad", bad), invalid_data)
    try expect_equal((try written(path)), before)

test "closing a logger twice keeps reporting Closed":
    let directory = try temporary("manuscript-log-")
    var logger = try create(try file_transport("{directory.path()}/out.ndjson"))
    try logger.close()
    try logger.close()

    let closed: Unit! = error(
        Error("logging: resource is closed", kind: ErrorCategory.Closed)
    )
    try expect_equal(logger.info("closed"), closed)
    try expect_equal(logger.flush(), closed)

test "file transport appends and flushes with scoped cleanup":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    var logger = try create(try file_transport(path), timestamp: false)
    try logger.info("first")
    try logger.flush()
    try logger.close()

    var logger2 = try create(try file_transport(path), timestamp: false)
    try logger2.warn("second")
    try logger2.close()

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
            ) != Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )
    )

test "stdout transport accepts records and leaves stdout open":
    let logger = try create(stdout_transport(), timestamp: false)
    try logger.info("stdout log")
    try logger.flush()

type CaptureTransport:
    path: String
    suffix: String

impl Transport for CaptureTransport:
    fn write(data: String) Unit!:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Unit!:
        if read_file("{self.path}{self.suffix}").is_ok(): return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        match append_file_bytes(self.path, data):
            ok(_): return ok(unit)
            error(cause): return error(cause)

    fn flush() Unit!:
        if read_file("{self.path}{self.suffix}").is_ok(): return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return ok(unit)

    fn duplicate() Transport!:
        return ok(CaptureTransport(self.path.clone(), "{self.suffix}.child"))

    fn close() Unit:
        let _marked = write_file("{self.path}{self.suffix}", "closed", true)

test "source transports receive complete records and close through their contract":
    let temporary = temporary("manuscript-log-transport-") | try expect_ok
    let path = "{temporary.path()}/records.ndjson"
    var logger = try create(CaptureTransport(path.clone(), ".closed"), timestamp: false)
    try logger.info("source transport")
    try logger.flush()
    try expect_equal(
        (read_file(path) | try expect_ok).decode_utf8(),
        "\{\"level\":30,\"msg\":\"source transport\"\}\n"
    )
    try logger.close()
    try expect_true(read_file("{path}.closed").is_ok())

fn log_from_child(logger: Logger) Unit!:
    let child = try logger.child("worker")
    return child.info("from child")

fn log_in_scope(path: String) Unit!:
    let logger = try create(CaptureTransport(path.clone(), ".closed"), timestamp: false)
    try log_from_child(logger)
    return logger.info("parent after child")

test "a logger scope closes its transport and a dropped child closes only its own":
    let temporary = temporary("manuscript-log-scope-") | try expect_ok
    let path = "{temporary.path()}/records.ndjson"
    try expect_ok(log_in_scope(path.clone()))
    try expect_true(read_file("{path}.closed").is_ok())
    try expect_true(read_file("{path}.closed.child").is_ok())

test "unencodable fields are rejected and fields keep their shape under data":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/out.ndjson"
    let file = try open(path: path, flags: "w", mode: 420)
    let logger = try create(handle_transport(file), timestamp: false)
    let invalid: Unit! = error(
        Error("logging: invalid data", kind: ErrorCategory.InvalidData)
    )
    let nan = JsonValue.NumberValue("NaN")
    try expect_equal(logger.info("m", nan), invalid)
    try expect_false(logger.child(nan).is_ok())
    try expect_equal((try written(path)), "")
    try logger.log(LogLevel.Info, "m", Service("a"))
    try logger.info("m", [1])

    let expected = "\{\"level\":30,\"msg\":\"m\",\"data\":\{\"service\":\"a\"\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":[1]\}\n"
    try expect_equal((try written(path)), expected)

fn chatter(logger: Logger, name: String) Unit!:
    for n in 0..3:
        try logger.info("m", name)
    return ok(unit)

test "loggers on several threads never interleave a record":
    let directory = try temporary("manuscript-log-threads-")
    let path = "{directory.path()}/out.ndjson"
    let logger = try create(try file_transport(path.clone()), timestamp: false)
    let first = try logger.child("a")
    let second = try logger.child("b")
    let a = promise(fn: chatter(first, "a"))
    let b = promise(fn: chatter(second, "b"))
    a.wait() | try expect_ok
    b.wait() | try expect_ok
    try logger.flush()

    let text = (try written(path)).get("")
    try expect_equal(text.split("\n").length(), 7)

    for line in text.split("\n"):
        if line != "":
            try expect_true(
                line.starts_with(
                    "\{\"level\":30,\"msg\":\"m\",\"context\":"
                )
            )
            try expect_true(line.ends_with("\}"))

// A transport that appends every record to a file.
type Memory:
    path: String

impl Transport for Memory:
    fn write(data: String) Unit!:
        return append_file(self.path, data)

    fn write_bytes(data: Bytes) Unit!:
        return self.write(data.decode_utf8().get(""))

    fn flush() Unit!:
        return ok(unit)

    fn duplicate() Transport!:
        return ok(Memory(self.path.clone()))

    fn close() Unit:
        return unit

fn recorded(path: String) String:
    return written(path).get(none).get("")

test "messages are escaped and fields keep their shape under data":
    let out_dir = try temporary("manuscript-log-memory-")
    let out = "{out_dir.path()}/records"
    let logger = try create(Memory(out.clone()), timestamp: false)
    try logger.info("a<b>&\"\n\t\u{1}é")
    try logger.info("m", Items([none, 1]))
    try logger.info("m", "text")
    try logger.info("m", JsonValue.Null)
    try logger.info("m", JsonValue.ObjectValue(Map[String, JsonValue]()))

    let expected = "\{\"level\":30,\"msg\":\"a<b>&\\\"\\n\\t\\u0001é\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\"items\":[null,1]\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\"text\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":null\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\}\}\n"
    try expect_equal(recorded(out.clone()), expected)

test "child context merges per child and the newer value wins":
    let out_dir = try temporary("manuscript-log-memory-")
    let out = "{out_dir.path()}/records"
    let root = try create(Memory(out.clone()), timestamp: false)
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
    try expect_equal(recorded(out.clone()), expected)

test "the time field is a millisecond count and the size limit counts the newline":
    let out_dir = try temporary("manuscript-log-memory-")
    let out = "{out_dir.path()}/records"
    let stamped = try create(Memory(out.clone()))
    try stamped.info("t")

    let line = recorded(out.clone())
    try expect_true(line.starts_with("\{\"level\":30,\"msg\":\"t\",\"time\":1"))

    let quiet_dir = try temporary("manuscript-log-memory-")
    let quiet = "{quiet_dir.path()}/records"
    let plain = "\{\"level\":30,\"msg\":\"ab\"\}\n"
    let exact = try create(
        Memory(quiet.clone()), timestamp: false, max_bytes: plain.to_bytes().length()
    )
    try exact.info("ab")
    try expect_equal(recorded(quiet.clone()), plain)

    let tight = try create(
        Memory(quiet.clone()), timestamp: false,
        max_bytes: plain.to_bytes().length() - 1
    )
    let limited: Unit! = error(
        Error("logging: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    try expect_equal(tight.info("ab"), limited)
    try expect_equal(recorded(quiet.clone()), plain)

test "rotating transport moves a full file aside and keeps a bounded number of generations":
    let directory = try temporary("manuscript-rotate-")
    let path = "{directory.path()}/app.log"
    var logger = try create(
        try rotating_file_transport(path.clone(), 80, 2), timestamp: false
    )
    for index in 0..12: try logger.info("record number {index}")
    try logger.flush()

    let current = (try written(path)).get("")
    let first = (try written("{path}.1")).get("")
    let second = (try written("{path}.2")).get("")
    try expect_true(current != "" and first != "" and second != "")
    try expect_true(current.to_bytes().length() <= 80)
    try expect_true(read_file("{path}.3").is_error())
    try expect_true(current.contains("record number 11"))
    try logger.close()
    try expect_true(logger.info("late").is_error())

test "rotating transport rejects invalid sizes":
    let directory = try temporary("manuscript-rotate-")
    let path = "{directory.path()}/app.log"
    try expect_true(rotating_file_transport(path.clone(), 0, 1).is_error())
    try expect_true(rotating_file_transport(path.clone(), 10, -1).is_error())
