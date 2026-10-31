# conform: tags=diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:70 TestCollectionPreludeAndShadowing
fn f(m: Map[String, Int]) Unit:
    m.add("a", true)
