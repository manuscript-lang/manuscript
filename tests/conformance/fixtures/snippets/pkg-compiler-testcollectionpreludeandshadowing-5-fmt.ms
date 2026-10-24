# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:57 TestCollectionPreludeAndShadowing
def identity[List, Map, Set](left: List, right: Map, other: Set) -> Set: other
