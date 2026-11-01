# conform: tags=formatter,lists,modules,optional,parser,records,stdlib-log,strings,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/logging/records.ms
import Logger, LogError, LogLevel, record from "@std/log.ms"

type Request:
    request: String

type Payload:
    count: Int
    ok: Bool
    nested: List[Bool?]
    service: String
    level: Int
    msg: String
    time: Int

export fn emit(logger: Logger) Unit!LogError:
    let child = try logger.child_json("\{\"request\":\"req-1\"\}")
    let fields = Payload(
        count: 9007199254740993, ok: true, nested: [none, false], service: "worker",
        level: 0, msg: "spoofed", time: 0
    )
    try child.debug("filtered")
    try record(
        logger: child, level: LogLevel.Info, message: "received \"payload\"\nnext",
        fields
    )
    try logger.warn("complete")
    return ok(unit)
