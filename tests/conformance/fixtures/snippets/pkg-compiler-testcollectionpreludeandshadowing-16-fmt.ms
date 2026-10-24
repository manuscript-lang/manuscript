# conform: tags=formatter,generics,parser,records,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:78 TestCollectionPreludeAndShadowing
type Set[T]:
    value: T

def f(values: Set[Int]) -> Unit:
    values.add(1)
