# JSON text laid out like CPython's `json.dumps` (ASCII-only output, `", "` and `": "` separators, or one
# item per line with `indent` spaces), so regenerated challenge files and result lines stay byte-identical.
import JsonValue, parse, stringify from "@std/json.ms"
import Data from "@std/core.ms"
import from_scalars from "@std/string.ms"

fn hex4(code: Int) String:
    let digits = "0123456789abcdef"
    return "\\u{digits.get(code / 4096)}{digits.get(code / 256 % 16)}{digits.get(code / 16 % 16)}{digits.get(code % 16)}"

fn quote(text: String) String:
    var out = "\""

    for code in text.scalar_values():
        if code == 34:
            out = out + "\\\""
        else if code == 92:
            out = out + "\\\\"
        else if code == 10:
            out = out + "\\n"
        else if code == 13:
            out = out + "\\r"
        else if code == 9:
            out = out + "\\t"
        else if code == 8:
            out = out + "\\b"
        else if code == 12:
            out = out + "\\f"
        else if code < 32 or (code > 126 and code < 65536):
            out = out + hex4(code)
        else if code >= 65536:
            let v = code - 65536
            out = out + hex4(55296 + v / 1024) + hex4(56320 + v % 1024)
        else:
            out = out + from_scalars([code]).get("")

    return out + "\""

fn emit(value: JsonValue, indent: Int, level: Int) String:
    match value:
        Null: return "null"
        BoolValue(flag): return if flag: "true" else: "false"
        NumberValue(text): return text.clone()
        StringValue(text): return quote(text)
        ArrayValue(items):
            if items.is_empty(): return "[]"

            let pad = " ".repeat((level + 1) * indent).get("")
            let end = " ".repeat(level * indent).get("")
            let parts = items.map(fn item: emit(item, indent, level + 1))
            if indent == 0: return "[" + parts.join(", ") + "]"

            return "[\n" + pad + parts.join(",\n" + pad) + "\n" + end + "]"
        ObjectValue(members):
            if members.is_empty(): return "\{\}"

            let pad = " ".repeat((level + 1) * indent).get("")
            let end = " ".repeat(level * indent).get("")
            var parts = List[String]()
            for entry in members.entries():
                parts.append(
                    quote(entry.key) + ": " + emit(
                        entry.value, indent, level + 1
                    )
                )
            if indent == 0: return "\{" + parts.join(", ") + "\}"

            return "\{\n" + pad + parts.join(",\n" + pad) + "\n" + end + "\}"

# Lays `value` out as `json.dumps(value, indent=indent)` does; `indent` 0 means the single-line form.
export fn dumps(value: JsonValue, indent: Int) String:
    return emit(value, indent, 0)

# Encodes any `Data` value, then lays it out as `dumps` does.
export fn dumps_data[T: Data](value: T, indent: Int) String:
    let text = stringify(value).get("null")
    let tree = parse(text).get(JsonValue.Null)
    return emit(tree, indent, 0)
