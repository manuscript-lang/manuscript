# conform: tags=diagnostics,maps,modules,records,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:75 TestCollectionPreludeAndShadowing
import Map from "@std/collections.ms"

type Map[K, V]:
    value: V
