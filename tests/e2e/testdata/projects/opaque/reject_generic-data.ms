import Approved, Mode, approve, safe from "./gate.ms"
import parse, stringify from "@std/json.ms"

fn wrap[T](v: T) String:
    return stringify(v).get("")

export fn main() Int:
    return wrap(approve("u")).length()
