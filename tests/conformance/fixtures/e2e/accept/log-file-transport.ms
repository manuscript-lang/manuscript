# conform: tags=lists,records,stdlib-fs,stdlib-log,stdlib-testing,testing,tier-io
# conform: phase=test
# conform: origin=perf thread: @std/log on the native backend
import expect_equal, expect_error from "@std/test.ms"
import LogError, LogLevel, create, file_transport, record from "@std/log.ms"
import FileSystemError, filesystem from "@std/fs.ms"

type Service:
    service: String

type Request:
    request: Int

fn lines(path: String) Result[String, Error]:
    let data = try filesystem().read_file(path)
    return ok(data.decode_utf8().get(""))

test "levels filter, fields nest under data, and bound fields merge":
    let fs = filesystem()
    let directory = try fs.temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    var logger = try create(try file_transport(path), LogLevel.Warn, false)
    try expect_equal(logger.enabled(LogLevel.Info), false)
    try logger.info("filtered")
    try logger.warn("warn")
    try record(logger, LogLevel.Error, "n", 7)
    try record(logger, LogLevel.Fatal, "l", ["a", "b"])

    let root = try logger.child_json("\{\"service\":\"api\"\}")
    let child = try root.child_json("\{\"request\":7\}")
    try record(child, LogLevel.Warn, "child", Service("worker"))
    logger.set_level(LogLevel.Trace)
    try expect_equal(logger.level(), LogLevel.Trace)
    try logger.trace("trace")
    try logger.flush()
    logger.close()

    let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"n\",\"data\":7\}\n\{\"level\":60,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n\{\"level\":40,\"msg\":\"child\",\"service\":\"worker\",\"request\":7\}\n\{\"level\":10,\"msg\":\"trace\"\}\n"
    try expect_equal(try lines(path), expected)

test "limits, invalid levels, and closed transports are errors":
    let fs = filesystem()
    let directory = try fs.temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
    var logger = try create(
        try file_transport(path), timestamp: false, max_bytes: line.to_bytes().length()
    )
    try logger.info("x")

    let limited: Result[Unit, LogError] = error(LogError.LimitExceeded)
    try expect_equal(logger.info("xx"), limited)

    let invalid: Result[Unit, LogError] = error(LogError.InvalidInput)
    try expect_equal(logger.log(LogLevel.Silent, "bad"), invalid)
    try expect_equal(
        try expect_error(create(try file_transport(path), max_bytes: -1)),
        LogError.InvalidInput
    )
    logger.close()
    logger.close()

    let closed: Result[Unit, LogError] = error(LogError.Closed)
    try expect_equal(logger.info("x"), closed)
    try expect_equal(logger.flush(), closed)
    try expect_equal(try lines(path), line)

test "a missing directory is a filesystem error":
    let fs = filesystem()
    let directory = try fs.temporary("manuscript-log-")
    let missing = try expect_error(
        file_transport("{directory.path()}/missing/events.ndjson")
    )
    try expect_equal(missing, LogError.FileSystem(FileSystemError.NotFound))
