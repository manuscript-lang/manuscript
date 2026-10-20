# conform: tags=diagnostics,generics,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:280 FuzzCompile
type Box[T]:
    value: T
fn f() Box[Int]:
    return Box(value: 1)
