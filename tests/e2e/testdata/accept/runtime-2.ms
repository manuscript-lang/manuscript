import panic from "@std/faults.ms"

type Items:
    count: Int

type Outcome:
    case Value(value: Int)

fn compute(value: Int) Int:
    return value

fn ordinary() Outcome:
    return Outcome.Value(compute(3))

test "non-prelude spellings are ordinary names":
    if not (Items(2).count == 2):
        return panic("check failed")

    let forward = compute
    if not (forward(4) == 4):
        return panic("check failed")

    match ordinary():
        Value(value):
            if not (value == 3):
                return panic("check failed")
