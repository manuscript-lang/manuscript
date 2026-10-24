# conform: tags=formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:76 TestCollectionPreludeAndShadowing
def f(values: Set[Int]) -> Unit:
    values.add(True)
