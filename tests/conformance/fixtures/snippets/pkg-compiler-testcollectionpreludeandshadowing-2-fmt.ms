# conform: tags=formatter,generics,lists,parser,records,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:37 TestCollectionPreludeAndShadowing
type Selection:
    values: Set[Int]
fn keep[T: Hashable](var values: Set[T], value: T) Set[T]:
    values.add(value)
    return values
fn use() Set[Int]:
    var values: Set[Int] = Set[Int]()
    let nested: List[Set[Int]] = [values]
    return keep(nested[0], 1)
