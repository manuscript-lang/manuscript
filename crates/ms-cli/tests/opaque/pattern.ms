import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

export fn main() Int:
    {entity} := approve("u")
    return entity.length()
