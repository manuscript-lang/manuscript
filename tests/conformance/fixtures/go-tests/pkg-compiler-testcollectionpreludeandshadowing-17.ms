# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:79 TestCollectionPreludeAndShadowing
fn f() Unit:
    let values = Set()
