# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:49 TestCollectionPreludeAndShadowing
def f() -> Int:
    let List = lambda (value: Int) -> Int: value
    let Map = lambda (value: Int) -> Int: value
    let Set = lambda (value: Int) -> Int: value
    let items = [1]
    let entries = {1: 2}
    return List(3) + Map(4) + Set(5) + items.length() + entries.length()
