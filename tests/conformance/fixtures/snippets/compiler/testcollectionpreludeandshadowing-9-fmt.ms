# conform: tags=formatter,lists,maps,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:71 TestCollectionPreludeAndShadowing
fn f(m: Map[List[Int], Int]) Unit:
    return
