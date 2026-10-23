import {Logger, LogError, LogLevel, record, bind} from "@std/log.ms"

type Request:
    request: String

type Payload:
    count: Int
    ok: Bool
    nested: List[Optional[Bool]]
    service: String
    level: Int
    msg: String
    time: Int

export fn emit(logger: Logger) Result[Unit, LogError]:
    let child = try bind(logger, Request("req-1"))
    let fields = Payload(
        count: 9007199254740993, ok: true, nested: [none, some(false)],
        service: "worker", level: 0, msg: "spoofed", time: 0
    )
    try child.debug("filtered")
    try record(
        logger: child, level: LogLevel.Info, message: "received \"payload\"\nnext",
        fields
    )
    try logger.warn("complete")
    return ok(unit)
