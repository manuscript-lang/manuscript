// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:57 TestCollectionPreludeAndShadowing
fn identity[List, Map, Set](left List, right Map, hold other Set) &Set => other
// expect-exit: 0
