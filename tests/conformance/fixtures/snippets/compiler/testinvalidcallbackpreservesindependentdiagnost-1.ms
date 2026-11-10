// conform: tags=closures,diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/callbacks_test.go:121 TestInvalidCallbackPreservesIndependentDiagnostics
fn example() Unit:
    names := [1, 2].map(fn item: missing).join(other_missing)
    conflict := apply(value: 1, transform: fn(item: String): missing_result)
    wrong: Int = "text"
    callback: fn(Int) Int = fn: missing_too
