import {Approved, Mode, approve, safe} from "./gate.ms"
import {parse, stringify} from "@std/json.ms"

export fn main() Int:
    let {entity} = approve("u")
    return entity.length()
