# conform: tags=diagnostics,modules,records,sets,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:81 TestCollectionPreludeAndShadowing
from "@std/collections.ms" import Set

type Set[T]:
    value: T
