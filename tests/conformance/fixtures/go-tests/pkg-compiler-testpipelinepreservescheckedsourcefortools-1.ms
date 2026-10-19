# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/pipeline_test.go:16 TestPipelinePreservesCheckedSourceForTools
fn value(flag: Bool = not false) Bool:
    let callback = fn() Bool: return not (false or false)
    return (not false and callback()) or flag
