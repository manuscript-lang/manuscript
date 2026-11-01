import Shared from "@std/concurrency/shared.ms"

export fn main() Int:
    let box = Shared(1)
    box = 2

    let value: Int = box
    return value
