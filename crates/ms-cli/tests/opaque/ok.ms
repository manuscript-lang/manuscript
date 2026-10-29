import {approve, entity, safe, wild, level} from "./gate.ms"
import {Approved} from "./gate.ms"

fn show[T](value: T) String:
    return "{value}"

export fn main() Int:
    let a = approve("u1")
    let b = a.clone()
    let line = "{a}" + a.to_string() + show(b) + a.label()
    if entity(a) != "u1" or level(safe()) != 0 or level(wild(3)) != 3: return 1
    return line.length()
