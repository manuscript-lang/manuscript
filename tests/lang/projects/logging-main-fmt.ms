// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/projects/logging/main.ms
import (
	JsonValue from "@std/data/json.ms",
	stderr from "@std/io/io.ms",
	LogLevel,
	Logger,
	create,
	file_transport,
	record,
	stdout_transport from "@std/log.ms",
	arguments from "@std/os/env.ms",

	emit from "./records.ms",
)

fn exercise(mode String, path String) Void! {
	if (mode == "file" or mode == "missing") {
		var root = create(file_transport(path)?, timestamp: false)?
		logger := root.child_json("{\"service\":\"api\"}")?
		emit(logger)?
		logger.flush()?
		root.close()?
		return ok()
	}

	if mode == "limit" {
		logger := create(stdout_transport(), max_bytes: 1)?
		logger.info("too large")?
	} else if mode == "closed" {
		var root = create(stdout_transport())?
		logger := root.child_json("{\"service\":\"api\"}")?
		root.close()?
		logger.info("closed")?
	} else {
		root := create(stdout_transport())?
		logger := root.child_json("{\"service\":\"api\"}")?

		if mode == "invalid" {
			record(
				logger,
				level: LogLevel.Info,
				message: "invalid",
				fields: JsonValue.NumberValue("NaN"),
			)?
		} else {
			emit(logger)?
			logger.flush()?
		}
	}

	var logger = create(stdout_transport(), timestamp: false)?
	logger.info("still open")?
	logger.close()?
}

export fn main() Int {
	args := arguments()
	mode := args.get(0, default: "stdout")
	path := args.get(1, default: "events.ndjson")
	result := exercise(mode, path)

	if result.is_error() {
		_ignored := stderr().write(f"{result.err().message}\n")
		return 1
	}

	return 0
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tJsonValue from "@std/data/json.ms",
// expect-formatted: \tstderr from "@std/io/io.ms",
// expect-formatted: \tLogLevel,
// expect-formatted: \tLogger,
// expect-formatted: \tcreate,
// expect-formatted: \tfile_transport,
// expect-formatted: \trecord,
// expect-formatted: \tstdout_transport from "@std/log.ms",
// expect-formatted: \targuments from "@std/os/env.ms",
// expect-formatted:
// expect-formatted: \temit from "./records.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: fn exercise(mode, path String) Void! {
// expect-formatted: \tif (mode == "file" or mode == "missing") {
// expect-formatted: \t\tvar root = create(file_transport(path)?, timestamp: false)?
// expect-formatted: \t\tlogger := root.child_json("{\\"service\\":\\"api\\"}")?
// expect-formatted: \t\temit(logger)?
// expect-formatted: \t\tlogger.flush()?
// expect-formatted: \t\troot.close()?
// expect-formatted: \t\treturn ok()
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tif mode == "limit" {
// expect-formatted: \t\tlogger := create(stdout_transport(), max_bytes: 1)?
// expect-formatted: \t\tlogger.info("too large")?
// expect-formatted: \t} else if mode == "closed" {
// expect-formatted: \t\tvar root = create(stdout_transport())?
// expect-formatted: \t\tlogger := root.child_json("{\\"service\\":\\"api\\"}")?
// expect-formatted: \t\troot.close()?
// expect-formatted: \t\tlogger.info("closed")?
// expect-formatted: \t} else {
// expect-formatted: \t\troot := create(stdout_transport())?
// expect-formatted: \t\tlogger := root.child_json("{\\"service\\":\\"api\\"}")?
// expect-formatted:
// expect-formatted: \t\tif mode == "invalid" {
// expect-formatted: \t\t\trecord(
// expect-formatted: \t\t\t\tlogger,
// expect-formatted: \t\t\t\tlevel: LogLevel.Info,
// expect-formatted: \t\t\t\tmessage: "invalid",
// expect-formatted: \t\t\t\tfields: JsonValue.NumberValue("NaN"),
// expect-formatted: \t\t\t)?
// expect-formatted: \t\t} else {
// expect-formatted: \t\t\temit(logger)?
// expect-formatted: \t\t\tlogger.flush()?
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar logger = create(stdout_transport(), timestamp: false)?
// expect-formatted: \tlogger.info("still open")?
// expect-formatted: \tlogger.close()?
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \targs := arguments()
// expect-formatted: \tmode := args.get(0, default: "stdout")
// expect-formatted: \tpath := args.get(1, default: "events.ndjson")
// expect-formatted: \tresult := exercise(mode, path)
// expect-formatted:
// expect-formatted: \tif result.is_error() {
// expect-formatted: \t\t_ignored := stderr().write(f"{result.err().message}\\n")
// expect-formatted: \t\treturn 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn 0
// expect-formatted: }
