import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn apply(value: Int, action: fn(value: Int) -> Int) -> Int:
    return action(value: value)

fn countdown[T](value: T, count: Int) -> T:
    if count == 0:
        return value
    return countdown(value: value, count: count - 1)

test "snapshot reassignment and shadowing":
    var offset = 1
    let action = fn(value: Int) -> Int:
        return value + offset
    offset = 10
    if not (action(value: 3) == 4):
        return panic(message: "check failed")
    if true:
        var offset = 20
        offset = 30
        if not (action(value: offset) == 31):
            return panic(message: "check failed")
    if not (offset == 10):
        return panic(message: "check failed")
    if not (countdown(value: "ready", count: 4) == "ready"):
        return panic(message: "check failed")
    let factory = fn(value: Int) -> fn(value: Int) -> Int:
        return fn(value: Int) -> Int:
            return value + offset
    let nested = factory(value: 99)
    offset = 100
    if not (nested(value: 1) == 11):
        return panic(message: "check failed")
