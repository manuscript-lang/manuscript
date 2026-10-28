# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:45 TestCollectionPreludeAndShadowing
fn use() Set[Int]:
    var values: Set[Int] = Set()
    values.add(1)
    return values
