# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/checker_test.go:91 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Growing[T]:
    children: List[Growing[List[T]]]
