# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/checker_test.go:107 TestBareIdentifiersArePositionalAndPreserveSourceAST
def first[T](left: T, right: T) -> T: return left

def call(left: Int, right: Int) -> Int: return first(right, left)
