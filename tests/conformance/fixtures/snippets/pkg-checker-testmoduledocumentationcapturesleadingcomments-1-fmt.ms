# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/documentation_test.go:179 TestModuleDocumentationCapturesLeadingComments
# Adds two numbers.
# Never rounds.
export fn add(a: Int, b: Int) Int:
    return a + b

# Detached by a blank line.

export fn sub(a: Int, b: Int) Int:
    return a - b

# Not a doc comment: private declaration.
fn helper() Int:
    return 1

export fn bare() Int:
    return 0
