import panic from "@std/faults.ms"

fn positive(value: Int) Int:
    if value > 0:
        return value
    else:
        panic("positive value required")

fn discard(value: Int) Unit:
    if not (value > 0):
        return panic("check failed")

test "return contracts":
    if not (positive(3) == 3):
        return panic("check failed")

    discard(1)
