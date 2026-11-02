import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

fn wrap[T](v: T) String:
    return stringify(v)

export fn main() Int:
    return wrap(approve("u")).length()
