import {Logger, LogLevel, create, record, stdout_transport, file_transport} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import arguments from "@std/process.ms"
import stderr from "@std/io.ms"
import emit from "./records.ms"

fn exercise(mode: String, path: String) Result[Unit, Error]:
    if (mode == "file" or mode == "missing"):
        with root = try create(try file_transport(path), timestamp: false):
            let logger = try root.child_json("\{\"service\":\"api\"\}")
            try emit(logger)
            try logger.flush()

        return ok(unit)

    if mode == "limit":
        with logger = try create(stdout_transport(), max_bytes: 1):
            try logger.info("too large")
    else if mode == "closed":
        var root = try create(stdout_transport())
        let logger = try root.child_json("\{\"service\":\"api\"\}")
        root.close()
        try logger.info("closed")
    else:
        with root = try create(stdout_transport()):
            let logger = try root.child_json("\{\"service\":\"api\"\}")

            if mode == "invalid":
                try record(
                    logger, level: LogLevel.Info, message: "invalid",
                    fields: JsonValue.NumberValue("NaN")
                )
            else:
                try emit(logger)
                try logger.flush()

    with logger = try create(stdout_transport(), timestamp: false):
        try logger.info("still open")
    return ok(unit)

export fn main() Int:
    let args = arguments()
    let mode = args.get(0, default: "stdout")
    let path = args.get(1, default: "events.ndjson")
    let result = exercise(mode, path)

    if result.is_error():
        let _ignored = stderr().write("{result.err().message()}\n")
        return 1

    return 0
