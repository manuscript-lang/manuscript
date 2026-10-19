# conform: tags=diagnostics,faults,lists,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:32 TestCollectionPreludeAndShadowing
fn use() Int:
    let nested: List[List[Int]] = [[], [1]]
    let empty: Map[String, Int] = {}
    return Map[String, Int]().add("a", nested[1][0]).get("a").get()
