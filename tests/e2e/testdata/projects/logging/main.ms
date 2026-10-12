import {Logger, create, stdout_transport, file_transport} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import {List, Map} from "@std/collections.ms"
import arguments from "@std/cli.ms"
import stderr from "@std/io.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import Error from "@std/errors.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import emit from "./records.ms"

fn concurrent_records(logger: Logger) -> Result[Unit, Error]:
    with group = TaskGroup():
        let tasks: List[Task[Result[Unit, Error]]] = []
        for worker in [0, 1, 2, 3, 4, 5, 6, 7]:
            let task = group.start(fn() -> Result[Unit, Error]:
                let bindings = Map[String, JsonValue]().with_entry(key: "worker", value: JsonValue.NumberValue(text: worker.toString()))
                let child = logger.child(bindings)
                for sequence in [0, 1, 2, 3, 4, 5, 6, 7]:
                    let fields = Map[String, JsonValue]().with_entry(key: "sequence", value: JsonValue.NumberValue(text: sequence.toString()))
                    let logged = try child.info(message: "concurrent", fields: some(value: fields))
                return ok(value: unit)
            )
            tasks.append(task)
        let joined = try group.join()
        for task in tasks:
            let outcome = try task.join()
            let completed = try outcome
    return ok(value: unit)

fn exercise(mode: String, path: String) -> Result[Unit, Error]:
    let bindings = Map[String, JsonValue]().with_entry(key: "service", value: JsonValue.StringValue(value: "api"))
    if mode == "file" or mode == "concurrent" or mode == "missing":
        with transport = try file_transport(path):
            let logger = try create(transport: transport, bindings: some(value: bindings), timestamp: some(value: false))
            if mode == "concurrent":
                let logged = try concurrent_records(logger)
            else:
                let logged = try emit(logger)
            let flushed = try logger.flush()
        return ok(value: unit)
    with transport = stdout_transport():
        if mode == "limit":
            let logger = try create(transport: transport, max_bytes: some(value: 1))
            let logged = try logger.info(message: "too large")
        else:
            let logger = try create(transport: transport, bindings: some(value: bindings))
            if mode == "invalid":
                let fields = Map[String, JsonValue]().with_entry(key: "bad", value: JsonValue.NumberValue(text: "NaN"))
                let logged = try logger.info(message: "invalid", fields: some(value: fields))
            else if mode == "closed":
                transport.close()
                let logged = try logger.info(message: "closed")
            else:
                let logged = try emit(logger)
                let flushed = try logger.flush()
    with transport = stdout_transport():
        let logger = try create(transport: transport, timestamp: some(value: false))
        let logged = try logger.info(message: "still open")
    return ok(value: unit)

export fn main() -> Int:
    let args = arguments()
    let mode = args.at(0).unwrap_or("stdout")
    let path = args.at(1).unwrap_or("events.ndjson")
    match exercise(mode: mode, path: path):
        ok(_): return 0
        error(cause):
            let diagnostic = stderr().write("{cause.message()}\n".to_bytes())
            return 1
