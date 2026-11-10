import (
    Approved, Mode, approve, safe from "./gate.ms",
    parse, stringify from "@std/data/json.ms",
)

export fn main() Int:
    let a = parse[Approved]("\{\}")
    return 0
