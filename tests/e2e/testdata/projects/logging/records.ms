from "@std/log.ms" import Logger, LogError, LogLevel, record

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

export def emit(logger: Logger) -> Result[Unit, LogError]:
    let child = try logger.child_json("{\"request\":\"req-1\"}")
    let fields = Payload(
        count: 9007199254740993, ok: True, nested: [none, some(False)],
        service: "worker", level: 0, msg: "spoofed", time: 0
    )
    try child.debug("filtered")
    try record(
        logger: child, level: LogLevel.Info, message: "received \"payload\"\nnext",
        fields
    )
    try logger.warn("complete")
    return ok(())
