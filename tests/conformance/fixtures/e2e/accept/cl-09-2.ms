# conform: tags=generics,optional,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-09-2.ms
fn absent[T]() T?:
    return none

test "result context infers function arguments":
    let _value: Int? = absent()
