# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:76 TestCollectionPreludeAndShadowing
def f(values: Set[Int]) -> Unit:
    values.add(True)
