# conform: tags=diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/checker_test.go:91 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Growing[T]:
    children: List[Growing[List[T]]]
