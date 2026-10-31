# conform: tags=formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:70 TestCollectionPreludeAndShadowing
fn f(m: Map[String, Int]) Unit:
    m.add("a", true)
