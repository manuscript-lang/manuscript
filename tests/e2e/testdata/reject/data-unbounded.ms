import stringify from "@std/data/json.ms"

fn show[T](value: T) String:
    return stringify(value).get("")

export fn main() Int:
    return show(1).length()
