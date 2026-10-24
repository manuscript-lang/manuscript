# conform: tags=diagnostics,lists,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:77 TestCollectionPreludeAndShadowing
def f(values: Set[List[Int]]) -> Unit:
    return
