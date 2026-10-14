import {Logger, LogError} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export fn emit(logger: Logger) -> Result[Unit, LogError]:
    let bindings = Map[String, JsonValue]().add(
        key: "request",
        value: JsonValue.StringValue("req-1")
    )
    let child = logger.child(bindings)
    let fields = Map[String, JsonValue]()
    fields.add(key: "count", value: JsonValue.NumberValue("9007199254740993"))
    fields.add(key: "ok", value: JsonValue.BoolValue(true))
    fields.add(
        key: "nested",
        value: JsonValue.ArrayValue(
            [JsonValue.Null, JsonValue.BoolValue(false)]
        )
    )
    fields.add(key: "service", value: JsonValue.StringValue("worker"))
    fields.add(key: "level", value: JsonValue.NumberValue("0"))
    fields.add(key: "msg", value: JsonValue.StringValue("spoofed"))
    fields.add(key: "time", value: JsonValue.NumberValue("0"))
    let ignored = try child.debug(message: "filtered")
    let received = try child.info(message: "received \"payload\"\nnext", fields: fields)
    let complete = try logger.warn(message: "complete")
    return ok(unit)
