# conform: tags=control-flow,diagnostics,faults,interpolation,modules,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,with-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/logging/main.ms
from "@std/log.ms" import Logger, LogLevel, create, record, stdout_transport, file_transport
from "@std/json.ms" import JsonValue
from "@std/process.ms" import arguments
from "@std/io.ms" import stderr
from "./records.ms" import emit

def exercise(mode: String, path: String) -> Result[Unit, Error]:
    if (mode == "file" or mode == "missing"):
        var root = try create(try file_transport(path), timestamp: False)
        let logger = try root.child_json("{\"service\":\"api\"}")
        try emit(logger)
        try logger.flush()
        root.close()
        return ok(())

    if mode == "limit":
        let logger = try create(stdout_transport(), max_bytes: 1)
        try logger.info("too large")
    elif mode == "closed":
        var root = try create(stdout_transport())
        let logger = try root.child_json("{\"service\":\"api\"}")
        root.close()
        try logger.info("closed")
    else:
        let root = try create(stdout_transport())
        let logger = try root.child_json("{\"service\":\"api\"}")

        if mode == "invalid":
            try record(
                logger, level: LogLevel.Info, message: "invalid",
                fields: JsonValue.NumberValue("NaN")
            )
        else:
            try emit(logger)
            try logger.flush()

    var logger = try create(stdout_transport(), timestamp: False)
    try logger.info("still open")
    logger.close()
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
