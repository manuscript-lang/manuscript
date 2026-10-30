import Approved, Mode, approve, safe from "./gate.ms"
import parse, stringify from "@std/json.ms"

export fn main() Int:
    var a = approve("u")
    a.nonce = "z"
    return 0
