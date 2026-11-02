# conform: tags=formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:45 TestCollectionPreludeAndShadowing
fn use() Set[Int]:
    var values: Set[Int] = Set()
    values.add(1)
    return values
