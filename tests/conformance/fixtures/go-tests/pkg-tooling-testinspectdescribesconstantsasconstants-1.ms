# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/inspect_constants_test.go:10 TestInspectDescribesConstantsAsConstants
let LIMIT = 10
fn size() Int:
    return LIMIT
