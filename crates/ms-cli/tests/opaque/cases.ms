import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/json.ms"

export fn main() Int:
    match safe():
        Safe: return 0
        _: return 1
