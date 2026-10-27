from "@std/test.ms" import expect_true

def keep(var list: List[Callable[[], Int]], value: Int) -> Unit:
    list.append(value: lambda () -> Int: value)
    return ()

def grow(var list: List[Int], value: Int) -> Int:
    list.append(value: value)
    return value

def nested(items: List[Int]) -> List[Int]:
    return items.map(
        lambda (value: Int) -> Int: (
            items.map(lambda (inner: Int) -> Int: inner + value).length()
            + value
        )
    )

test "list callbacks":
    var items = List[Int]()
    var i = 0

    while i < 5:
        items.append(value: i)
        i = i + 1

    let doubled = items.map(lambda (value: Int) -> Int: value * 2)
    try expect_true((doubled.get(index: 4) == 8))

    let even = items.filter(lambda (value: Int) -> Bool: value % 2 == 0)
    try expect_true((even.length() == 3))
    try expect_true(
        (
            items.fold(
                initial: 0,
                step: lambda (accumulator: Int, value: Int) -> Int: (
                    accumulator
                    + value
                )
            ) == 10
        )
    )
    try expect_true(
        (items.count(predicate: lambda (value: Int) -> Bool: value > 1) == 3)
    )

    var retained = List[Callable[[], Int]]()
    for value in items:
        keep(list: var retained, value: value)

    let called = retained.map(lambda (value: Callable[[], Int]) -> Int: value())
    try expect_true(
        (
            called.fold(
                initial: 0,
                step: lambda (accumulator: Int, value: Int) -> Int: (
                    accumulator
                    + value
                )
            ) == 10
        )
    )

    var grown = List[Int]()
    grown.append(value: 1)
    grown.append(value: 2)

    var seen = List[Int]()
    for value in grown.clone():
        seen.append(value: grow(list: var grown, value: value))
    try expect_true((seen.length() == 2 and grown.length() == 4))
    try expect_true((nested(items: items).get(index: 2) == 7))
