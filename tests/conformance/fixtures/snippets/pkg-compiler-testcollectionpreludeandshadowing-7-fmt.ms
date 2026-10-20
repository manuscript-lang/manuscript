# conform: tags=formatter,maps,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:69 TestCollectionPreludeAndShadowing
type Map[K, V]:
    value: V
fn f() Unit:
    let xs = {1: 2}
