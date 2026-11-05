// conform: tags=alternatives,control-flow,formatter,generics,interfaces,match,parser,records,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/tooling/pattern_lint_test.go:28 TestPatternBindingAdvisory
enum Failure[T]:
    case NotFound
    case Denied(reason: T)

fn use[T](value: Result[Int, Failure[T]]) Int:
    match value:
        error(_): return 1
        ok(inner): return inner
