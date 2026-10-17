import {Logger, LogLevel, create, bind, record, stdout_transport, file_transport} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import arguments from "@std/cli.ms"
import stderr from "@std/io.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import emit from "./records.ms"

type Worker:
    worker: Int

type Sequence:
    sequence: Int

type Service:
    service: String

fn concurrent_records(logger: Logger) -> Result[Unit, Error]:
    with group = TaskGroup():
        let tasks: List[Task[Result[Unit, Error]]] = []

        for worker in [0, 1, 2, 3, 4, 5, 6, 7]:
            let task = group.start(
                fn() -> Result[Unit, Error]:
                    let child = try bind(
                        logger: logger,
                        bindings: Worker(worker: worker)
                    )
                    for sequence in [0, 1, 2, 3, 4, 5, 6, 7]:
                        let logged = try record(
                            logger: child,
                            level: LogLevel.Info,
                            message: "concurrent",
                            fields: Sequence(
                                sequence: sequence
                            )
                        )
                    return ok(unit)
            )
            tasks.append(task)

        let joined = try group.join()

        for task in tasks:
            let outcome = try task.join()
            let completed = try outcome

    return ok(unit)

fn exercise(mode: String, path: String) -> Result[Unit, Error]:
    let bindings = Service(service: "api")

    if (mode == "file" or mode == "concurrent" or mode == "missing"):
        with transport = try file_transport(path):
            let logger = try create(transport: transport, timestamp: false)
                | try bind(bindings: bindings)

            if mode == "concurrent":
                let logged = try concurrent_records(logger)
            else:
                let logged = try emit(logger)

            let flushed = try logger.flush()

        return ok(unit)

    with transport = stdout_transport():
        if mode == "limit":
            let logged = try create(transport: transport, max_bytes: 1)
                | try .info(message: "too large")
        else:
            let logger = try create(transport: transport)
                | try bind(bindings: bindings)

            if mode == "invalid":
                let logged = try record(
                    logger: logger,
                    level: LogLevel.Info,
                    message: "invalid",
                    fields: JsonValue.NumberValue("NaN")
                )
            else if mode == "closed":
                transport.close()
                let logged = try logger.info(message: "closed")
            else:
                let logged = try emit(logger)
                let flushed = try logger.flush()

    with transport = stdout_transport():
        let logger = try create(transport: transport, timestamp: false)
        let logged = try logger.info(message: "still open")

    return ok(unit)

export fn main() -> Int:
    let args = arguments()
    let mode = args.at(0).unwrap_or("stdout")
    let path = args.at(1).unwrap_or("events.ndjson")
    let result = exercise(mode: mode, path: path)
    if result.is_ok(): return 0

    let diagnostic = stderr().write("{result.unwrap_error().message()}\n".to_bytes())
    return 1
