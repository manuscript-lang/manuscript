// conform: tags=diagnostics,maps,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:73 TestCollectionPreludeAndShadowing
fn f(m Map[Int, Int]) Void:
    m.add(1)
