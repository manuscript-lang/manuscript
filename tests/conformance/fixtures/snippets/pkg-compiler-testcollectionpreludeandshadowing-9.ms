# conform: tags=diagnostics,lists,maps,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:71 TestCollectionPreludeAndShadowing
def f(m: Map[List[Int], Int]) -> Unit:
    return
