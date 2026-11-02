# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:48 TestPipelineChecksSkippedBooleanOperands
fn value() Bool: return true or 3
