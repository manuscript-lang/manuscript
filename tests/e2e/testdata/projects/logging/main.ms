from "@std/log.ms" import Logger, LogLevel, create, record, stdout_transport, file_transport
from "@std/json.ms" import JsonValue
from "@std/process.ms" import arguments
from "@std/io.ms" import stderr
from "./records.ms" import emit

def exercise(mode: String, path: String) -> Result[Unit, Error]:
    if (mode == "file" or mode == "missing"):
        with try create(try file_transport(path), timestamp: False) as root:
            let logger = try root.child_json("{\"service\":\"api\"}")
            try emit(logger)
            try logger.flush()

        return ok(())

    if mode == "limit":
        with try create(stdout_transport(), max_bytes: 1) as logger:
            try logger.info("too large")
    elif mode == "closed":
        var root = try create(stdout_transport())
        let logger = try root.child_json("{\"service\":\"api\"}")
        root.close()
        try logger.info("closed")
    else:
        with try create(stdout_transport()) as root:
            let logger = try root.child_json("{\"service\":\"api\"}")

            if mode == "invalid":
                try record(
                    logger, level: LogLevel.Info, message: "invalid",
                    fields: JsonValue.NumberValue("NaN")
                )
            else:
                try emit(logger)
                try logger.flush()

    with try create(stdout_transport(), timestamp: False) as logger:
        try logger.info("still open")
    return ok(())

export def main() -> Int:
    let args = arguments()
    let mode = args.get(0, default: "stdout")
    let path = args.get(1, default: "events.ndjson")
    let result = exercise(mode, path)

    if result.is_error():
        let _ignored = stderr().write(f"{result.err().message()}\n")
        return 1

    return 0
