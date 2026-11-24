import (
	JsonValue from "@std/data/json.ms",
	stderr from "@std/io/io.ms",
	Logger, LoggerOptions, create, file_transport, stdout_transport from "@std/log.ms",
	arguments from "@std/os/env.ms",

	emit from "./records.ms",
)

type Service:
	service String

fn exercise(mode String, path String) Void!:
	if (mode == "file" or mode == "missing"):
		var root = create(file_transport(path)?, LoggerOptions(timestamp: false))?
		logger := root.child(Service("api"))?
		emit(logger)?
		logger.flush()?
		root.close()?
		return ok()

	if mode == "limit":
		logger := create(stdout_transport(), LoggerOptions(max_bytes: 1))?
		logger.info("too large")?
	else if mode == "closed":
		var root = create(stdout_transport())?
		logger := root.child(Service("api"))?
		root.close()?
		logger.info("closed")?
	else:
		root := create(stdout_transport())?
		logger := root.child(Service("api"))?

		if mode == "invalid":
			logger.info("invalid", JsonValue.NumberValue("NaN"))?
		else:
			emit(logger)?
			logger.flush()?

	var logger = create(stdout_transport(), LoggerOptions(timestamp: false))?
	logger.info("still open")?
	logger.close()?

export fn main() Int:
	args := arguments()
	mode := args.get_or(0, "stdout")
	path := args.get_or(1, "events.ndjson")
	result := exercise(mode, path)

	if result.is_error():
		_ignored := stderr().write(f"{result.err().message}\n")
		return 1

	return 0
