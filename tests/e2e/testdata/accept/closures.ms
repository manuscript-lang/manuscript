import panic from "@std/faults.ms"

fn apply(value: Int, action: fn(value: Int) Int) Int:
    return action(value)

fn countdown[T](value: T, count: Int) T:
    if count == 0:
        return value

    return countdown(value, count - 1)

test "snapshot reassignment and shadowing":
    var offset = 1
    let action = fn(value: Int):
        return value + offset
    offset = 10
    if not (action(3) == 4):
        return panic("check failed")

    if true:
        var offset = 20
        offset = 30
        if not (action(offset) == 31):
            return panic("check failed")

    if not (offset == 10):
        return panic("check failed")
    if not (countdown("ready", 4) == "ready"):
        return panic("check failed")

    let factory = fn(value: Int) fn(value: Int) Int:
        return fn(value):
            return value + offset
    let nested = factory(value: 99)
    offset = 100
    if not (nested(1) == 11):
        return panic("check failed")
