# conform: tags=diagnostics,maps,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:69 TestCollectionPreludeAndShadowing
type Map[K, V]:
    value: V
fn f() Unit:
    let xs = {1: 2}
