# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/logging/main.ms
import Logger, LogLevel, create, record, stdout_transport, file_transport from "@std/log.ms"
import JsonValue from "@std/data/json.ms"
import arguments from "@std/os/process.ms"
import stderr from "@std/io/io.ms"
import emit from "./records.ms"

fn exercise(mode: String, path: String) Unit!:
    if (mode == "file" or mode == "missing"):
        var root = try create(try file_transport(path), timestamp: false)
        let logger = try root.child_json("\{\"service\":\"api\"\}")
        try emit(logger)
        try logger.flush()
        root.close()
        return ok(unit)

    if mode == "limit":
        let logger = try create(stdout_transport(), max_bytes: 1)
        try logger.info("too large")
    else if mode == "closed":
        var root = try create(stdout_transport())
        let logger = try root.child_json("\{\"service\":\"api\"\}")
        root.close()
        try logger.info("closed")
    else:
        let root = try create(stdout_transport())
        let logger = try root.child_json("\{\"service\":\"api\"\}")

        if mode == "invalid":
            try record(
                logger, level: LogLevel.Info, message: "invalid",
                fields: JsonValue.NumberValue("NaN")
            )
        else:
            try emit(logger)
            try logger.flush()

    var logger = try create(stdout_transport(), timestamp: false)
    try logger.info("still open")
    logger.close()
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
