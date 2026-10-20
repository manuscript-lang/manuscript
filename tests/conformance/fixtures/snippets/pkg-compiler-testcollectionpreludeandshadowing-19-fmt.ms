# conform: tags=formatter,modules,parser,records,sets,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:81 TestCollectionPreludeAndShadowing
import Set from "@std/collections.ms"
type Set[T]:
    value: T
