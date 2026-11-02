# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:79 TestCollectionPreludeAndShadowing
fn f() Unit:
    let values = Set()
