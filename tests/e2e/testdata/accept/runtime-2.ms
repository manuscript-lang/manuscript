type List:
    count: Int

type Result:
    case Value(value: Int)

fn parallel(value: Int) -> Int:
    return value

fn ordinary() -> Result:
    return Result.Value(value: parallel(value: 3))

test "standard spellings are ordinary names":
    assert List(count: 2).count == 2
    let forward = parallel
    assert forward(value: 4) == 4
    match ordinary():
        Value(value):
            assert value == 3
