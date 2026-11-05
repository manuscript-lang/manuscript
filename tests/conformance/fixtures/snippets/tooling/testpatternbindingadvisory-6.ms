// conform: tags=alternatives,control-flow,diagnostics,generics,interfaces,match,records,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:28 TestPatternBindingAdvisory
enum Failure[T]:
    NotFound
    Denied(reason: T)

fn use[T](value: Result[Int, Failure[T]]) Int:
    match value:
        error(_): return 1
        ok(inner): return inner
