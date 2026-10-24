# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:9 TestDefaultClosureAssignmentReferencesAndListHints
def answer(
    value: Int = (
        lambda () -> Int:
            var current = 0
            current = current + 1
            return current
    )()
) -> Int:
    let callbacks = [
        lambda () -> Int:
            let nested = 1
            return nested
    ]
    return value + callbacks.length()
