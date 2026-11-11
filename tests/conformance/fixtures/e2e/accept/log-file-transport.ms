// conform: tags=lists,records,stdlib-fs,stdlib-log,stdlib-testing,testing,tier-io
// conform: phase=test
// conform: origin=perf thread: @std/log on the native backend
import (
	LogLevel, LoggerOptions, create, file_transport from "@std/log.ms",
	read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

type Service:
	service: String

type Request:
	request: Int

fn lines(path: String) String!:
	data := read_file(path).wait()?
	return ok(data.decode_utf8().get(""))

test "levels filter, fields nest under data, and bound fields merge":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/events.ndjson"
	var logger = create(
		file_transport(path)?, LoggerOptions(level: LogLevel.Warn, timestamp: false)
	)?
	expect_equal(logger.enabled(LogLevel.Info), false)?
	logger.info("filtered")?
	logger.warn("warn")?
	logger.error("n", 7)?
	logger.fatal("l", ["a", "b"])?

	root := logger.child(Service("api"))?
	child := root.child(Request(7))?
	child.warn("child", Service("worker"))?
	logger.set_level(LogLevel.Trace)
	expect_equal(logger.level(), LogLevel.Trace)?
	logger.trace("trace")?
	logger.flush()?
	logger.close()?

	expected := "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"n\",\"data\":7\}\n\{\"level\":60,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n\{\"level\":40,\"msg\":\"child\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"service\":\"worker\"\}\}\n\{\"level\":10,\"msg\":\"trace\"\}\n"
	expect_equal(lines(path)?, expected)?

test "limits, invalid levels, and closed transports are errors":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/events.ndjson"
	line := "\{\"level\":30,\"msg\":\"x\"\}\n"
	var logger = create(
		file_transport(path)?,
		LoggerOptions(timestamp: false, max_bytes: line.to_bytes().length())
	)?
	logger.info("x")?

	limited: Unit! := error(Error("logging: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(logger.info("xx"), limited)?

	invalid: Unit! := error(Error("logging: invalid input", kind: "EINVAL"))
	expect_equal(logger.log(LogLevel.Silent, "bad"), invalid)?
	expect_equal(
		expect_error(
			create(file_transport(path)?, LoggerOptions(max_bytes: -1))
		)?,
		Error("logging: invalid input", kind: "EINVAL")
	)?
	logger.close()?
	logger.close()?

	closed: Unit! := error(Error("logging: resource is closed", kind: "EBADF"))
	expect_equal(logger.info("x"), closed)?
	expect_equal(logger.flush(), closed)?
	expect_equal(lines(path)?, line)?

test "a missing directory is a filesystem error":
	directory := temporary("manuscript-log-")?
	missing := expect_error(file_transport("{directory.path()}/missing/events.ndjson"))?
	expect_equal(missing.kind, "ENOENT")?
	expect_equal(
		missing.message,
		"filesystem: file or directory not found: {directory.path()}/missing/events.ndjson"
	)?
