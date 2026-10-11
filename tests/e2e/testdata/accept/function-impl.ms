type Apply[T]:
    fn apply(value: Int) -> T

type Box[T]:
    value: T

impl[T] Apply[T] for Box[fn(value: Int) -> T]:
    fn apply(value: Int) -> T:
        return self.value(value: value)

fn render(value: Int) -> String:
    return "{value}"

test "implementation variables inside function signatures":
    let box = Box(value: render)
    assert box.apply(value: 3) == "3"
    let operation = Apply[String](value: box)
    assert operation.apply(value: 4) == "4"
