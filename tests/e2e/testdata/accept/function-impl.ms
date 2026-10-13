import panic from "@std/faults.ms"

interface Apply[T]:
    fn apply(value: Int) -> T

type Box[T]:
    value: T

impl Apply[T] for Box[fn(value: Int) -> T]:
    fn apply(value: Int) -> T:
        return self.value(value: value)

fn render(value: Int) -> String:
    return "{value}"

test "implementation variables inside function signatures":
    let box = Box(render)
    if not (box.apply(value: 3) == "3"):
        return panic(message: "check failed")

    let operation = Apply[String](box)
    if not (operation.apply(value: 4) == "4"):
        return panic(message: "check failed")
