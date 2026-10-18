import {Logger, LogLevel, create, bind, record, stdout_transport, file_transport} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import arguments from "@std/process.ms"
import stderr from "@std/io.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import range from "@std/collections.ms"
import emit from "./records.ms"

type Worker:
    worker: Int

type Sequence:
    sequence: Int

type Service:
    service: String

fn concurrent_records(logger: Logger) Result[Unit, Error]:
    with group = TaskGroup():
        let tasks: List[Task[Result[Unit, Error]]] = []

        for worker in range(0, 8):
            let task = group.start(
                fn() Result[Unit, Error]:
                    let child = try bind(logger, Worker(worker))
                    for sequence in range(0, 8):
                        try record(
                            logger: child,
                            level: LogLevel.Info,
                            message: "concurrent",
                            fields: Sequence(sequence)
                        )
                    return ok(unit)
            )
            tasks.append(task)

        try group.join()

        for task in tasks:
            let outcome = try task.join()
            if outcome.is_error():
                return outcome

    return ok(unit)

fn exercise(mode: String, path: String) Result[Unit, Error]:
    let bindings = Service("api")

    if (mode == "file" or mode == "concurrent" or mode == "missing"):
        with transport = try file_transport(path):
            let logger = try create(transport, timestamp: false)
                | try bind(bindings)

            if mode == "concurrent":
                try concurrent_records(logger)
            else:
                try emit(logger)

            try logger.flush()

        return ok(unit)

    with transport = stdout_transport():
        if mode == "limit":
            let logger = try create(transport, max_bytes: 1)
            try logger.info("too large")
        else:
            let logger = try create(transport)
                | try bind(bindings)

            if mode == "invalid":
                try record(
                    logger,
                    level: LogLevel.Info,
                    message: "invalid",
                    fields: JsonValue.NumberValue("NaN")
                )
            else if mode == "closed":
                transport.close()
                try logger.info("closed")
            else:
                try emit(logger)
                try logger.flush()

    with transport = stdout_transport():
        let logger = try create(transport, timestamp: false)
        try logger.info("still open")

    return ok(unit)

export fn main() Int:
    let args = arguments()
    let mode = args.at(0).get("stdout")
    let path = args.at(1).get("events.ndjson")
    let result = exercise(mode, path)

    if result.is_error():
        let _ignored = stderr().write("{result.err().message()}\n")
        return 1

    return 0
