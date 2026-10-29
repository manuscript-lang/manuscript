# conform: tags=formatter,generics,optional,parser,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-09-2.ms
fn absent[T]() Optional[T]:
    return none

test "result context infers function arguments":
    let _value: Optional[Int] = absent()
