import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

fn main() Unit:
    let a = Approved(entity: "u2", nonce: "x")
