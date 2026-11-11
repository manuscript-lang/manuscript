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

fn exercise(mode: String, path: String) Unit!:
	if (mode == "file" or mode == "missing"):
		var root = create(file_transport(path)?, timestamp: false)?
		logger := root.child_json("\{\"service\":\"api\"\}")?
		emit(logger)?
		logger.flush()?
		root.close()?
		return ok(unit)

	if mode == "limit":
		logger := create(stdout_transport(), max_bytes: 1)?
		logger.info("too large")?
	else if mode == "closed":
		var root = create(stdout_transport())?
		logger := root.child_json("\{\"service\":\"api\"\}")?
		root.close()?
		logger.info("closed")?
	else:
		root := create(stdout_transport())?
		logger := root.child_json("\{\"service\":\"api\"\}")?

		if mode == "invalid":
			record(
				logger, level: LogLevel.Info, message: "invalid",
				fields: JsonValue.NumberValue("NaN")
			)?
		else:
			emit(logger)?
			logger.flush()?

	var logger = create(stdout_transport(), timestamp: false)?
	logger.info("still open")?
	logger.close()?

export fn main() Int:
	args := arguments()
	mode := args.get(0, default: "stdout")
	path := args.get(1, default: "events.ndjson")
	result := exercise(mode, path)

	if result.is_error():
		_ignored := stderr().write("{result.err().message}\n")
		return 1

	return 0
