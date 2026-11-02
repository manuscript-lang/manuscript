import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

export fn main() Int:
    match safe():
        Safe: return 0
        _: return 1
