# conform: tags=closures,formatter,generics,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/recursive_types_test.go:14 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Grow[T]:
    next: fn() Grow[List[T]]
export fn main() Int: return 0
