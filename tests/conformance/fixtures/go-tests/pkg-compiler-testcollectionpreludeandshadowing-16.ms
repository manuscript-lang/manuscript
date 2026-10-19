# conform: tags=diagnostics,generics,records,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:78 TestCollectionPreludeAndShadowing
type Set[T]:
    value: T
fn f(values: Set[Int]) Unit:
    values.add(1)
