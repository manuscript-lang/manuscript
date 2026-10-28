# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/logging/main.ms
from "@std/log.ms" import Logger, LogLevel, create, bind, record, stdout_transport, file_transport
from "@std/json.ms" import JsonValue
from "@std/process.ms" import arguments
from "@std/io.ms" import stderr
from "./records.ms" import emit

type Service:
    service: String

def exercise(mode: String, path: String) -> Result[Unit, Error]:
    let bindings = Service("api")

    if (mode == "file" or mode == "missing"):
        var transport = try file_transport(path)
        let logger = try create(transport, timestamp: False)
            | try bind(bindings)
        try emit(logger)
        try logger.flush()
        transport.close()
        return ok(())

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
        elif mode == "closed":
            transport.close()
            try logger.info("closed")
        else:
            try emit(logger)
            try logger.flush()

    transport.close()

    var transport2 = stdout_transport()
    let logger = try create(transport2, timestamp: False)
    try logger.info("still open")
    transport2.close()
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
