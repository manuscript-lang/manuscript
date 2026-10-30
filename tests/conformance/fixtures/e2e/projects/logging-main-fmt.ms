# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/logging/main.ms
import Logger, LogLevel, create, bind, record, stdout_transport, file_transport from "@std/log.ms"
import JsonValue from "@std/json.ms"
import arguments from "@std/process.ms"
import stderr from "@std/io.ms"
import emit from "./records.ms"

type Service:
    service: String

fn exercise(mode: String, path: String) Result[Unit, Error]:
    let bindings = Service("api")

    if (mode == "file" or mode == "missing"):
        var transport = try file_transport(path)
        let logger = try create(transport, timestamp: false)
            | try bind(bindings)
        try emit(logger)
        try logger.flush()
        transport.close()
        return ok(unit)

    var transport = stdout_transport()

    if mode == "limit":
        let logger = try create(transport, max_bytes: 1)
        try logger.info("too large")
    else:
        let logger = try create(transport)
            | try bind(bindings)

        if mode == "invalid":
            try record(
                logger, level: LogLevel.Info, message: "invalid",
                fields: JsonValue.NumberValue("NaN")
            )
        else if mode == "closed":
            transport.close()
            try logger.info("closed")
        else:
            try emit(logger)
            try logger.flush()

    transport.close()

    var transport2 = stdout_transport()
    let logger = try create(transport2, timestamp: false)
    try logger.info("still open")
    transport2.close()
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
