import (
    Approved, Mode, approve, safe from "./gate.ms",
    parse, stringify from "@std/data/json.ms",
)

export fn main() Int:
    {entity} := approve("u")
    return entity.length()
