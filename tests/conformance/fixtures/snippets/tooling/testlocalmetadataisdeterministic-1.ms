# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/inspect_locals_test.go:11 TestLocalMetadataIsDeterministic
fn answer(input: Int) Int:
    let value = input
    return value
