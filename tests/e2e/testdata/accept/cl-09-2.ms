fn absent[T]() T?:
    return none

test "result context infers function arguments":
    let _value: Int? = absent()
