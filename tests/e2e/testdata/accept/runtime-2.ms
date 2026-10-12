import panic from "@std/faults.ms"

type List:
    count: Int

type Result:
    case Value(value: Int)

fn parallel(value: Int) -> Int:
    return value

fn ordinary() -> Result:
    return Result.Value(value: parallel(value: 3))

test "standard spellings are ordinary names":
    if not (List(count: 2).count == 2):
        return panic(message: "check failed")
    let forward = parallel
    if not (forward(value: 4) == 4):
        return panic(message: "check failed")
    match ordinary():
        Value(value):
            if not (value == 3):
                return panic(message: "check failed")
