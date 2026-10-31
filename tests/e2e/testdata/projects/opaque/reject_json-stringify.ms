import Approved, Mode, approve, safe from "./gate.ms"
import parse, stringify from "@std/json.ms"

export fn main() Int:
    let s = stringify(approve("u"))
    return 0
