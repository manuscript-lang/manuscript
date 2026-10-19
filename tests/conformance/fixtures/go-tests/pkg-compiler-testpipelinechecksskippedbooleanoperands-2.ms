# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/pipeline_test.go:48 TestPipelineChecksSkippedBooleanOperands
fn value() Bool: return true or 3
