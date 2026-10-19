# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:57 TestCollectionPreludeAndShadowing
fn identity[List, Map, Set](left: List, right: Map, other: Set) Set: other
