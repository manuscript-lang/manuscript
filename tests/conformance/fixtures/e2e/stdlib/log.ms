// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	promise from "@std/concurrency/promise.ms",
	JsonValue from "@std/data/json.ms",
	LogLevel,
	Logger,
	LoggerOptions,
	Transport,
	create,
	file_transport,
	handle_transport,
	rotating_file_transport,
	stdout_transport from "@std/log.ms",
	OpenMode,
	OpenOptions,
	append_file,
	open,
	read_file,
	temporary,
	write_file from "@std/os/fs.ms",
	expect_equal,
	expect_error,
	expect_false,
	expect_ok,
	expect_true from "@std/test/test.ms",
)

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
	data := read_file(path).wait()?
	return ok(data.decode_utf8())

test "logger writes typed escaped records and protects metadata":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	var logger = create(file_transport(path.clone())?, LoggerOptions(timestamp: false))?
	fields := Payload(9007199254740993, ok: true, Items([none, 1]), 0, "fake", 0)
	logger.info("say \"hi\"\nnext", fields)?

	expected := "\{\"level\":30,\"msg\":\"say \\\"hi\\\"\\nnext\",\"data\":\{\"count\":9007199254740993,\"ok\":true,\"nested\":\{\"items\":[null,1]\},\"level\":0,\"msg\":\"fake\",\"time\":0\}\}\n"
	expect_equal((written(path)?), expected)?
	logger.flush()?
	logger.close()?
	expect_true(logger.info("late").is_error())?

test "non-object values are written under data":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	file := open(path, OpenMode.Write, OpenOptions(permissions: 420))?
	logger := create(handle_transport(file), LoggerOptions(timestamp: false))?
	logger.info("n", 7)?
	logger.warn("l", ["a", "b"])?

	expected := "\{\"level\":30,\"msg\":\"n\",\"data\":7\}\n\{\"level\":40,\"msg\":\"l\",\"data\":[\"a\",\"b\"]\}\n"
	expect_equal((written(path)?), expected)?

test "levels filter methods and function values":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	file := open(path, OpenMode.Write, OpenOptions(permissions: 420))?
	var logger = create(
		handle_transport(file),
		LoggerOptions(level: LogLevel.Warn, timestamp: false),
	)?
	expect_false((logger.enabled(LogLevel.Info) or not logger.enabled(LogLevel.Warn)))?
	logger.trace("filtered")?
	logger.debug("filtered")?
	logger.info("filtered")?
	expect_equal((written(path)?), "")?
	logger.warn("warn")?

	error_log := logger.error[Unit]
	error_log("error")?
	logger.fatal("fatal")?
	logger.set_level(LogLevel.Trace)
	expect_equal(logger.level(), LogLevel.Trace)?
	logger.log(LogLevel.Trace, "trace")?
	logger.debug("debug")?
	logger.info("info")?

	expected := "\{\"level\":40,\"msg\":\"warn\"\}\n\{\"level\":50,\"msg\":\"error\"\}\n\{\"level\":60,\"msg\":\"fatal\"\}\n\{\"level\":10,\"msg\":\"trace\"\}\n\{\"level\":20,\"msg\":\"debug\"\}\n\{\"level\":30,\"msg\":\"info\"\}\n"
	expect_equal((written(path)?), expected)?
	logger.set_level(LogLevel.Silent)
	expect_false((logger.enabled(LogLevel.Fatal) or logger.enabled(LogLevel.Silent)))?

	before := written(path)?
	logger.fatal("filtered")?
	expect_equal((written(path)?), before)?

	invalid: Unit! := error(Error("logging: invalid input", kind: "EINVAL"))
	expect_equal(logger.log(LogLevel.Silent, "invalid"), invalid)?

type Service:
	service: String

type Request:
	request: Int

test "child bindings snapshot values and merge without mutating inputs":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	file := open(path, OpenMode.Write, OpenOptions(permissions: 420))?
	root := create(handle_transport(file), LoggerOptions(timestamp: false))?
	var logger = root.child(Service("api"))?
	child := logger.child(Request(7))?
	logger.set_level(LogLevel.Fatal)
	expect_equal(child.level(), LogLevel.Info)?
	child.info("child", Service("worker"))?
	logger.fatal("parent")?

	expected := "\{\"level\":30,\"msg\":\"child\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"service\":\"worker\"\}\}\n\{\"level\":60,\"msg\":\"parent\",\"context\":\{\"service\":\"api\"\}\}\n"
	expect_equal((written(path)?), expected)?

test "limits and unencodable values reject before writing":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	line := "\{\"level\":30,\"msg\":\"x\"\}\n"
	logger := create(
		file_transport(path.clone())?,
		LoggerOptions(timestamp: false, max_bytes: line.to_bytes().length()),
	)?
	logger.info("x")?
	expect_equal((written(path)?), line)?

	before := written(path)?
	limited: Unit! := error(Error("logging: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(logger.info("xx"), limited)?

	zero := create(
		file_transport(path.clone())?,
		LoggerOptions(timestamp: false, max_bytes: 0),
	)?
	expect_equal(zero.info(""), limited)?
	expect_false(
		(
			(
				expect_error(
					create(
						file_transport(path.clone())?,
						LoggerOptions(max_bytes: -1),
					)
				)?
			) != Error("logging: invalid input", kind: "EINVAL")
		)
	)?

	unlimited := create(file_transport(path.clone())?, LoggerOptions(timestamp: false))?
	bad := JsonValue.NumberValue("NaN")
	invalid_data: Unit! := error(Error("logging: invalid data", kind: "EBADMSG"))
	expect_equal(unlimited.info("bad", bad), invalid_data)?
	expect_equal((written(path)?), before)?

test "closing a logger twice keeps reporting Closed":
	directory := temporary("manuscript-log-")?
	var logger = create(file_transport("{directory.path()}/out.ndjson")?)?
	logger.close()?
	logger.close()?

	closed: Unit! := error(Error("logging: resource is closed", kind: "EBADF"))
	expect_equal(logger.info("closed"), closed)?
	expect_equal(logger.flush(), closed)?

test "file transport appends and flushes with scoped cleanup":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/events.ndjson"
	var logger = create(file_transport(path)?, LoggerOptions(timestamp: false))?
	logger.info("first")?
	logger.flush()?
	logger.close()?

	var logger2 = create(file_transport(path)?, LoggerOptions(timestamp: false))?
	logger2.warn("second")?
	logger2.close()?

	data := read_file(path).wait()?
	expect_false(
		(
			data.decode_utf8() != "\{\"level\":30,\"msg\":\"first\"\}\n\{\"level\":40,\"msg\":\"second\"\}\n"
		)
	)?

	missing := "{directory.path()}/missing/events.ndjson"
	refused := expect_error(file_transport(missing))?
	expect_equal(refused.kind, "ENOENT")?
	expect_equal(refused.message, "filesystem: file or directory not found: {missing}")?

test "stdout transport accepts records and leaves stdout open":
	logger := create(stdout_transport(), LoggerOptions(timestamp: false))?
	logger.info("stdout log")?
	logger.flush()?

type CaptureTransport:
	path: String
	suffix: String

fn CaptureTransport.write(data: String) Unit!:
	return self.write_bytes(data.to_bytes())

fn CaptureTransport.write_bytes(data: Bytes) Unit!:
	if read_file("{self.path}{self.suffix}").wait().is_ok(): return error(
		Error("logging: resource is closed", kind: "EBADF")
	)

	match append_file(self.path, data).wait():
		ok(_): return ok(unit)
		error(cause): return error(cause)

fn CaptureTransport.flush() Unit!:
	if read_file("{self.path}{self.suffix}").wait().is_ok(): return error(
		Error("logging: resource is closed", kind: "EBADF")
	)

fn CaptureTransport.duplicate() Transport!:
	return ok(CaptureTransport(self.path.clone(), "{self.suffix}.child"))

fn CaptureTransport.close() Unit:
	_marked := write_file("{self.path}{self.suffix}", "closed", true).wait()

test "source transports receive complete records and close through their contract":
	temporary := temporary("manuscript-log-transport-") | expect_ok?
	path := "{temporary.path()}/records.ndjson"
	var logger = create(
		CaptureTransport(path.clone(), ".closed"),
		LoggerOptions(timestamp: false),
	)?
	logger.info("source transport")?
	logger.flush()?
	expect_equal(
		(read_file(path).wait() | expect_ok?).decode_utf8(),
		"\{\"level\":30,\"msg\":\"source transport\"\}\n",
	)?
	logger.close()?
	expect_true(read_file("{path}.closed").wait().is_ok())?

fn log_from_child(logger: Logger) Unit!:
	child := logger.child("worker")?
	return child.info("from child")

fn log_in_scope(path: String) Unit!:
	logger := create(
		CaptureTransport(path.clone(), ".closed"),
		LoggerOptions(timestamp: false),
	)?
	log_from_child(logger)?
	return logger.info("parent after child")

test "a logger scope closes its transport and a dropped child closes only its own":
	temporary := temporary("manuscript-log-scope-") | expect_ok?
	path := "{temporary.path()}/records.ndjson"
	expect_ok(log_in_scope(path.clone()))?
	expect_true(read_file("{path}.closed").wait().is_ok())?
	expect_true(read_file("{path}.closed.child").wait().is_ok())?

test "unencodable fields are rejected and fields keep their shape under data":
	directory := temporary("manuscript-log-")?
	path := "{directory.path()}/out.ndjson"
	file := open(path, OpenMode.Write, OpenOptions(permissions: 420))?
	logger := create(handle_transport(file), LoggerOptions(timestamp: false))?
	invalid: Unit! := error(Error("logging: invalid data", kind: "EBADMSG"))
	nan := JsonValue.NumberValue("NaN")
	expect_equal(logger.info("m", nan), invalid)?
	expect_false(logger.child(nan).is_ok())?
	expect_equal((written(path)?), "")?
	logger.log(LogLevel.Info, "m", Service("a"))?
	logger.info("m", [1])?

	expected := "\{\"level\":30,\"msg\":\"m\",\"data\":\{\"service\":\"a\"\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":[1]\}\n"
	expect_equal((written(path)?), expected)?

fn chatter(logger: Logger, name: String) Unit!:
	for n in 0..3:
		logger.info("m", name)?

test "loggers on several threads never interleave a record":
	directory := temporary("manuscript-log-threads-")?
	path := "{directory.path()}/out.ndjson"
	logger := create(file_transport(path.clone())?, LoggerOptions(timestamp: false))?
	first := logger.child("a")?
	second := logger.child("b")?
	a := promise(fn: chatter(first, "a"))
	b := promise(fn: chatter(second, "b"))
	a.wait() | expect_ok?
	b.wait() | expect_ok?
	logger.flush()?

	text := (written(path)?).get("")
	expect_equal(text.split("\n").length(), 7)?

	for line in text.split("\n"):
		if line != "":
			expect_true(line.starts_with("\{\"level\":30,\"msg\":\"m\",\"context\":"))?
			expect_true(line.ends_with("\}"))?

// A transport that appends every record to a file.
type Memory:
	path: String

fn Memory.write(data: String) Unit!:
	return append_file(self.path, data).wait()

fn Memory.write_bytes(data: Bytes) Unit!:
	return self.write(data.decode_utf8().get(""))

fn Memory.flush() Unit!:
	return ok(unit)

fn Memory.duplicate() Transport!:
	return ok(Memory(self.path.clone()))

fn Memory.close() Unit:
	return unit

fn recorded(path: String) String:
	return written(path).get(none).get("")

test "messages are escaped and fields keep their shape under data":
	out_dir := temporary("manuscript-log-memory-")?
	out := "{out_dir.path()}/records"
	logger := create(Memory(out.clone()), LoggerOptions(timestamp: false))?
	logger.info("a<b>&\"\n\t\u{1}é")?
	logger.info("m", Items([none, 1]))?
	logger.info("m", "text")?
	logger.info("m", JsonValue.Null)?
	logger.info("m", JsonValue.ObjectValue(Map[String, JsonValue]()))?

	expected := "\{\"level\":30,\"msg\":\"a<b>&\\\"\\n\\t\\u0001é\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\"items\":[null,1]\}\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\"text\"\}\n\{\"level\":30,\"msg\":\"m\",\"data\":null\}\n\{\"level\":30,\"msg\":\"m\",\"data\":\{\}\}\n"
	expect_equal(recorded(out.clone()), expected)?

test "child context merges per child and the newer value wins":
	out_dir := temporary("manuscript-log-memory-")?
	out := "{out_dir.path()}/records"
	root := create(Memory(out.clone()), LoggerOptions(timestamp: false))?
	api := root.child(Service("api"))?
	both := api.child(Request(7))?
	renamed := both.child(Service("worker"))?
	replaced := both.child(3)?
	root.info("root")?
	api.info("api")?
	both.info("both", Request(9))?
	renamed.info("renamed")?
	replaced.info("replaced")?

	expected := "\{\"level\":30,\"msg\":\"root\"\}\n\{\"level\":30,\"msg\":\"api\",\"context\":\{\"service\":\"api\"\}\}\n\{\"level\":30,\"msg\":\"both\",\"context\":\{\"service\":\"api\",\"request\":7\},\"data\":\{\"request\":9\}\}\n\{\"level\":30,\"msg\":\"renamed\",\"context\":\{\"service\":\"worker\",\"request\":7\}\}\n\{\"level\":30,\"msg\":\"replaced\",\"context\":3\}\n"
	expect_equal(recorded(out.clone()), expected)?

test "the time field is a millisecond count and the size limit counts the newline":
	out_dir := temporary("manuscript-log-memory-")?
	out := "{out_dir.path()}/records"
	stamped := create(Memory(out.clone()))?
	stamped.info("t")?

	line := recorded(out.clone())
	expect_true(line.starts_with("\{\"level\":30,\"msg\":\"t\",\"time\":1"))?

	quiet_dir := temporary("manuscript-log-memory-")?
	quiet := "{quiet_dir.path()}/records"
	plain := "\{\"level\":30,\"msg\":\"ab\"\}\n"
	exact := create(
		Memory(quiet.clone()),
		LoggerOptions(timestamp: false, max_bytes: plain.to_bytes().length()),
	)?
	exact.info("ab")?
	expect_equal(recorded(quiet.clone()), plain)?

	tight := create(
		Memory(quiet.clone()),
		LoggerOptions(
			timestamp: false,
			max_bytes: plain.to_bytes().length() - 1,
		),
	)?
	limited: Unit! := error(Error("logging: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(tight.info("ab"), limited)?
	expect_equal(recorded(quiet.clone()), plain)?

test "rotating transport moves a full file aside and keeps a bounded number of generations":
	directory := temporary("manuscript-rotate-")?
	path := "{directory.path()}/app.log"
	var logger = create(
		rotating_file_transport(path.clone(), 80, 2)?,
		LoggerOptions(timestamp: false),
	)?
	for index in 0..12: logger.info("record number {index}")?
	logger.flush()?

	current := (written(path)?).get("")
	first := (written("{path}.1")?).get("")
	second := (written("{path}.2")?).get("")
	expect_true(current != "" and first != "" and second != "")?
	expect_true(current.to_bytes().length() <= 80)?
	expect_true(read_file("{path}.3").wait().is_error())?
	expect_true(current.contains("record number 11"))?
	logger.close()?
	expect_true(logger.info("late").is_error())?

test "rotating transport rejects invalid sizes":
	directory := temporary("manuscript-rotate-")?
	path := "{directory.path()}/app.log"
	expect_true(rotating_file_transport(path.clone(), 0, 1).is_error())?
	expect_true(rotating_file_transport(path.clone(), 10, -1).is_error())?
