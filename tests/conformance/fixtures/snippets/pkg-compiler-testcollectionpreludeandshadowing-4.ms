# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:49 TestCollectionPreludeAndShadowing
fn f() Int:
    let List = fn(value: Int) Int: value
    let Map = fn(value: Int) Int: value
    let Set = fn(value: Int) Int: value
    let items = [1]
    let entries = {1: 2}
    return List(3) + Map(4) + Set(5) + items.length() + entries.length()
