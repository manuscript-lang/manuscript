// conform: tags=closures,diagnostics,mutation,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/defaults_test.go:9 TestDefaultClosureAssignmentReferencesAndListHints
fn answer(
    value: Int = (
        fn() Int:
            var current = 0
            current = current + 1
            return current
    )()
) Int:
    callbacks := [
        fn() Int:
            nested := 1
            return nested
    ]
    return value + callbacks.length()
