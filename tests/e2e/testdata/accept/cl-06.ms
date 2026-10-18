import panic from "@std/faults.ms"

fn positive(value: Int) Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) Unit:
    if not (value > 0):
        return panic(message: "check failed")

test "return contracts":
    if not (positive(value: 3) == 3):
        return panic(message: "check failed")

    discard(value: 1)
