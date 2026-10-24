# conform: tags=diagnostics,maps,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:72 TestCollectionPreludeAndShadowing
type Map[K, V]:
    value: V

def f(m: Map[String, Int]) -> Unit:
    m.add("a", 1)
