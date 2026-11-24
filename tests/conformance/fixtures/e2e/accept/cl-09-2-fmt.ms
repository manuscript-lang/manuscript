// conform: tags=formatter,generics,optional,parser,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/cl-09-2.ms
fn absent[T]() T?:
    return null

test "result context infers function arguments":
    _value: Int? := absent()
