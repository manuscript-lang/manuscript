import parse, JsonValue, JsonError from "@std/data/json.ms"

export fn main() Int:
    let n = 50000
    let text = "{"[".repeat(n).get()}1{"]".repeat(n).get()}"
    let r: Result[JsonValue, JsonError] = parse(text)
    if r.is_error():
        return 1

    return 0
