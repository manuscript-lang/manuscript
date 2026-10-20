# conform: tags=diagnostics,maps,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:73 TestCollectionPreludeAndShadowing
fn f(m: Map[Int,Int]) Unit:
    m.add(1)
