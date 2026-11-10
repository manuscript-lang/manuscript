import (
    Approved, Mode, approve, safe from "./gate.ms",
    parse, stringify from "@std/data/json.ms",
)

export fn main() Int:
    let s = stringify(approve("u"))
    return 0
