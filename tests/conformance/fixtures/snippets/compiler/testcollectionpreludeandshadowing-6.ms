# conform: tags=diagnostics,generics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:68 TestCollectionPreludeAndShadowing
type List[T]:
    value: T

fn f() Unit:
    let xs = [1]
