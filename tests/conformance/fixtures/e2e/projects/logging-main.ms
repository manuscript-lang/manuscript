// conform: tags=control-flow,diagnostics,faults,interpolation,modules,records,stdlib-io,stdlib-json,stdlib-log,stdlib-process,strings,tier-io,try-result,scope-cleanup
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/logging/main.ms
import (
    Logger,
    LogLevel,
    create,
    record,
    stdout_transport,
    file_transport
) from "@std/log.ms"
import JsonValue from "@std/data/json.ms"
import arguments from "@std/os/env.ms"
import stderr from "@std/io/io.ms"
import emit from "./records.ms"

fn exercise(mode: String, path: String) Unit!:
    if (mode == "file" or mode == "missing"):
        var root = try create(try file_transport(path), timestamp: false)
        logger := try root.child_json("\{\"service\":\"api\"\}")
        try emit(logger)
        try logger.flush()
        try root.close()
        return ok(unit)

    if mode == "limit":
        logger := try create(stdout_transport(), max_bytes: 1)
        try logger.info("too large")
    else if mode == "closed":
        var root = try create(stdout_transport())
        logger := try root.child_json("\{\"service\":\"api\"\}")
        try root.close()
        try logger.info("closed")
    else:
        root := try create(stdout_transport())
        logger := try root.child_json("\{\"service\":\"api\"\}")

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
    try logger.close()
    return ok(unit)

export fn main() Int:
    args := arguments()
    mode := args.get(0, default: "stdout")
    path := args.get(1, default: "events.ndjson")
    result := exercise(mode, path)

    if result.is_error():
        _ignored := stderr().write("{result.err().message}\n")
        return 1

    return 0
