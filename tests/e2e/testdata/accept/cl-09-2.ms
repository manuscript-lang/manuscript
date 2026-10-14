import Optional from "@std/optional.ms"

fn absent[T]() -> Optional[T]:
    return none

test "result context infers function arguments":
    let value: Optional[Int] = absent()
