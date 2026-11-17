import parse, JsonValue from "@std/data/json.ms"

export fn main() Int:
    n := 50000
    text := f"{"[".repeat(n)}1{"]".repeat(n)}"
    r: Result[JsonValue, Error] := parse(text)
    if r.is_error():
        return 1

    return 0
