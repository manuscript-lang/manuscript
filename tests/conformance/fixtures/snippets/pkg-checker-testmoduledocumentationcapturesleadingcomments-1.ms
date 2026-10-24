# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/documentation_test.go:179 TestModuleDocumentationCapturesLeadingComments
# Adds two numbers.
# Never rounds.
export def add(a: Int, b: Int) -> Int:
    return a + b

# Detached by a blank line.
export def sub(a: Int, b: Int) -> Int:
    return a - b

# Not a doc comment: private declaration.
def helper() -> Int:
    return 1

export def bare() -> Int:
    return 0
