# conform: tags=formatter,maps,modules,parser,records,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:75 TestCollectionPreludeAndShadowing
from "@std/collections.ms" import Map

type Map[K, V]:
    value: V
