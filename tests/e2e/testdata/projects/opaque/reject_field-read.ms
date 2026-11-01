import Approved, Mode, approve, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

export fn main() Int:
    return approve("u").nonce.length()
