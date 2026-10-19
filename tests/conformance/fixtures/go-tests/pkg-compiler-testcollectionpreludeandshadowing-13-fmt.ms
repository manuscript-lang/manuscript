# conform: tags=formatter,maps,modules,parser,records,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:75 TestCollectionPreludeAndShadowing
import Map from "@std/collections.ms"
type Map[K,V]:
    value: V
