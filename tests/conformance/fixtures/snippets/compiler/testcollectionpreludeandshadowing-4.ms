// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:49 TestCollectionPreludeAndShadowing
fn f() Int:
    List := fn(value: Int) Int: value
    Map := fn(value: Int) Int: value
    Set := fn(value: Int) Int: value
    items := [1]
    entries := {1: 2}
    return List(3) + Map(4) + Set(5) + items.length() + entries.length()
