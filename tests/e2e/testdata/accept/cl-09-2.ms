def absent[T]() -> Optional[T]:
    return none

test "result context infers function arguments":
    let _value: Optional[Int] = absent()
