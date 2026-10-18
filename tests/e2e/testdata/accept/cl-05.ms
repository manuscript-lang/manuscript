import panic from "@std/faults.ms"

fn increase(value: Int) Int:
    return value + 1

fn apply(value: Int, transform: fn(value: Int) Int) Int:
    return transform(value)

test "function label compatibility":
    let transform: fn(value: Int) Int = increase
    if not (apply(4, transform) == 5):
        return panic("check failed")
