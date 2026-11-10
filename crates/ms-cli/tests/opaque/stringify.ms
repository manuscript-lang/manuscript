import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

export fn main() Int:
    s := stringify(approve("u"))
    return 0
