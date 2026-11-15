import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

fn main() Void:
    var a = approve("u")
    a.nonce = "z"
