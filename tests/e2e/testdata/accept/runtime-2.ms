import panic from "@std/faults.ms"

type List:
    count: Int

type Result:
    case Value(value: Int)

fn compute(value: Int) -> Int:
    return value

fn ordinary() -> Result:
    return Result.Value(compute(value: 3))

test "standard spellings are ordinary names":
    if not (List(2).count == 2):
        return panic(message: "check failed")

    let forward = compute
    if not (forward(value: 4) == 4):
        return panic(message: "check failed")

    match ordinary():
        Value(value):
            if not (value == 3):
                return panic(message: "check failed")
