import Optional from "@std/optional.ms"

fn absent[T]() -> Optional[T]:
    return none

test "result context does not infer function arguments":
    let value: Optional[Int] = absent[Int]()
