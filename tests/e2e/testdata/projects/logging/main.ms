import (
    Logger, LoggerOptions, create, stdout_transport, file_transport from "@std/log.ms",
    JsonValue from "@std/data/json.ms",
    arguments from "@std/os/env.ms",
    stderr from "@std/io/io.ms",
    emit from "./records.ms",
)

type Service:
    service: String

fn exercise(mode: String, path: String) Unit!:
    if (mode == "file" or mode == "missing"):
        var root = try create(try file_transport(path), LoggerOptions(timestamp: false))
        logger := try root.child(Service("api"))
        try emit(logger)
        try logger.flush()
        try root.close()
        return ok(unit)

    if mode == "limit":
        logger := try create(stdout_transport(), LoggerOptions(max_bytes: 1))
        try logger.info("too large")
    else if mode == "closed":
        var root = try create(stdout_transport())
        logger := try root.child(Service("api"))
        try root.close()
        try logger.info("closed")
    else:
        root := try create(stdout_transport())
        logger := try root.child(Service("api"))

        if mode == "invalid":
            try logger.info("invalid", JsonValue.NumberValue("NaN"))
        else:
            try emit(logger)
            try logger.flush()

    var logger = try create(stdout_transport(), LoggerOptions(timestamp: false))
    try logger.info("still open")
    try logger.close()

export fn main() Int:
    args := arguments()
    mode := args.get(0, default: "stdout")
    path := args.get(1, default: "events.ndjson")
    result := exercise(mode, path)

    if result.is_error():
        _ignored := stderr().write("{result.err().message}\n")
        return 1

    return 0
