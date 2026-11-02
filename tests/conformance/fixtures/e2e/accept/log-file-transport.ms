# conform: tags=lists,records,stdlib-fs,stdlib-log,stdlib-testing,testing,tier-io
# conform: phase=test
# conform: origin=perf thread: @std/log on the native backend
import expect_equal, expect_error from "@std/test/test.ms"
import LogLevel, create, file_transport from "@std/log.ms"
import read_file, temporary from "@std/os/fs.ms"

type Service:
    service: String

type Request:
    request: Int

fn lines(path: String) String!:
    let data = try read_file(path)
    return ok(data.decode_utf8().get(""))

test "levels filter, fields nest under data, and bound fields merge":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    var logger = try create(try file_transport(path), LogLevel.Warn, false)
    try expect_equal(logger.enabled(LogLevel.Info), false)
    try logger.info("filtered")
    try logger.warn("warn")
    try logger.error("n", 7)
    try logger.fatal("l", ["a", "b"])

    let root = try logger.child(Service("api"))
    let child = try root.child(Request(7))
    try child.warn("child", Service("worker"))
    logger.set_level(LogLevel.Trace)
    try expect_equal(logger.level(), LogLevel.Trace)
    try logger.trace("trace")
    try logger.flush()
    logger.close()

    let expected = "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"n\",\"data\":7\}\n\{\"level\":60,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n\{\"level\":40,\"msg\":\"child\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"service\":\"worker\"\}\}\n\{\"level\":10,\"msg\":\"trace\"\}\n"
    try expect_equal(try lines(path), expected)

test "limits, invalid levels, and closed transports are errors":
    let directory = try temporary("manuscript-log-")
    let path = "{directory.path()}/events.ndjson"
    let line = "\{\"level\":30,\"msg\":\"x\"\}\n"
    var logger = try create(
        try file_transport(path), timestamp: false, max_bytes: line.to_bytes().length()
    )
    try logger.info("x")

    let limited: Unit! = error(Error("logging: limit exceeded", kind: ErrorCategory.LimitExceeded))
    try expect_equal(logger.info("xx"), limited)

    let invalid: Unit! = error(Error("logging: invalid input", kind: ErrorCategory.InvalidInput))
    try expect_equal(logger.log(LogLevel.Silent, "bad"), invalid)
    try expect_equal(
        try expect_error(create(try file_transport(path), max_bytes: -1)),
        Error("logging: invalid input", kind: ErrorCategory.InvalidInput)
    )
    logger.close()
    logger.close()

    let closed: Unit! = error(Error("logging: resource is closed", kind: ErrorCategory.Closed))
    try expect_equal(logger.info("x"), closed)
    try expect_equal(logger.flush(), closed)
    try expect_equal(try lines(path), line)

test "a missing directory is a filesystem error":
    let directory = try temporary("manuscript-log-")
    let missing = try expect_error(
        file_transport("{directory.path()}/missing/events.ndjson")
    )
    try expect_equal(missing, Error("filesystem: file or directory not found", kind: ErrorCategory.NotFound))
