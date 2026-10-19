# conform: tags=formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:45 TestCollectionPreludeAndShadowing
fn use() Set[Int]:
    let values: Set[Int] = Set()
    return values.add(1)
