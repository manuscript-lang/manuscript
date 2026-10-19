# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:48 TestRecursiveTypesPreserveInitializationAndHashing
type Pair:
    left: Int
    right: Int
fn hash(pair: Pair) Int: return pair.hash()
