// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:57 TestCollectionPreludeAndShadowing
fn identity[List, Map, Set](left List, right Map, hold other Set) &Set => other
// expect-exit: 0
