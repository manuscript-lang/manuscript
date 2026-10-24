# conform: tags=generics,optional,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-09-2.ms
def absent[T]() -> Optional[T]:
    return none

test "result context infers function arguments":
    let _value: Optional[Int] = absent()
