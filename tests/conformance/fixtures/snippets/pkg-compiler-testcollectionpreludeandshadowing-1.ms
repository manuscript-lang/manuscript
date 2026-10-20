# conform: tags=diagnostics,faults,lists,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:32 TestCollectionPreludeAndShadowing
fn use() Int:
    let nested: List[List[Int]] = [[], [1]]
    let empty: Map[String, Int] = {}
    var chain_1 = Map[String, Int]()
    chain_1.add("a", nested[1][0])
    return chain_1.get("a").get()
