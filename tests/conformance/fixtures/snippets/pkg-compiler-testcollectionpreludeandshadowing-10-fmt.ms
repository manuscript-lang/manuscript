# conform: tags=formatter,maps,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:72 TestCollectionPreludeAndShadowing
type Map[K, V]:
    value: V

fn f(m: Map[String, Int]) Unit:
    m.add("a", 1)
