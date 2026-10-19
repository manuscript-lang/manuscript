# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:45 TestCollectionPreludeAndShadowing
fn use() Set[Int]:
    let values: Set[Int] = Set()
    return values.add(1)
