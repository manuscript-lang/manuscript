fn absent[T]() -> Optional[T]:
    return none

test "result context infers function arguments":
    let value: Optional[Int] = absent()
