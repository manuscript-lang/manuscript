import {Logger, LogError} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export fn emit(logger: Logger) -> Result[Unit, LogError]:
    let bindings = Map[String, JsonValue]().with_entry(
        key: "request",
        value: JsonValue.StringValue(value: "req-1")
    )
    let child = logger.child(bindings)
    let fields = Map[String, JsonValue]()
    fields.with_entry(
        key: "count",
        value: JsonValue.NumberValue(text: "9007199254740993")
    )
    fields.with_entry(
        key: "ok",
        value: JsonValue.BoolValue(value: true)
    )
    fields.with_entry(
        key: "nested",
        value: JsonValue.ArrayValue(
            values: [JsonValue.Null, JsonValue.BoolValue(value: false)]
        )
    )
    fields.with_entry(
        key: "service",
        value: JsonValue.StringValue(value: "worker")
    )
    fields.with_entry(
        key: "level",
        value: JsonValue.NumberValue(text: "0")
    )
    fields.with_entry(
        key: "msg",
        value: JsonValue.StringValue(value: "spoofed")
    )
    fields.with_entry(
        key: "time",
        value: JsonValue.NumberValue(text: "0")
    )
    let ignored = try child.debug(message: "filtered")
    let received = try child.info(
        message: "received \"payload\"\nnext",
        fields: fields
    )
    let complete = try logger.warn(message: "complete")
    return ok(value: unit)
