// conform: tags=formatter,maps,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/prelude_test.go:73 TestCollectionPreludeAndShadowing
fn f(m Map[Int, Int]) Void:
    m.add(1)
