# conform: tags=closures,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/callbacks_test.go:121 TestInvalidCallbackPreservesIndependentDiagnostics
def example() -> Unit:
    let names = [1, 2].map(lambda item: missing).join(other_missing)
    let conflict = apply(value: 1, transform: lambda (item: String): missing_result)
    let wrong: Int = "text"
    let callback: Callable[[Int], Int] = lambda: missing_too
