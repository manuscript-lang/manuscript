# conform: tags=closures,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:121 TestInvalidCallbackPreservesIndependentDiagnostics
fn example() Unit:
    let names = [1, 2].map(fn item: missing).join(other_missing)
    let conflict = apply(value: 1, transform: fn(item: String): missing_result)
    let wrong: Int = "text"
    let callback: fn(Int) Int = fn: missing_too
