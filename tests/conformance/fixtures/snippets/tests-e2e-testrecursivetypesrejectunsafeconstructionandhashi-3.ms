# conform: tags=closures,diagnostics,generics,lists,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/recursive_types_test.go:14 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Grow[T]:
    next: Callable[[], Grow[List[T]]]

export def main() -> Int: return 0
