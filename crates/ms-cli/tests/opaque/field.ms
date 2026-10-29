import {approve, Approved, Mode, safe} from "./gate.ms"
import {parse, stringify} from "@std/json.ms"

export fn main() Int:
    return approve("u").nonce.length()
