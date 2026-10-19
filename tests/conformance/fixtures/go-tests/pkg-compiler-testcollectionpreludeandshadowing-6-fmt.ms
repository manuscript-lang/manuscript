# conform: tags=formatter,generics,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:68 TestCollectionPreludeAndShadowing
type List[T]:
    value: T
fn f() Unit:
    let xs = [1]
