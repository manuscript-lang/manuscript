# conform: tags=formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:73 TestCollectionPreludeAndShadowing
def f(m: Map[Int, Int]) -> Unit:
    m.add(1)
