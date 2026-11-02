# conform: tags=diagnostics,lists,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:77 TestCollectionPreludeAndShadowing
fn f(values: Set[List[Int]]) Unit:
    return
