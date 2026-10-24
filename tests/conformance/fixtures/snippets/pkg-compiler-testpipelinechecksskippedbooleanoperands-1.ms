# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/pipeline_test.go:47 TestPipelineChecksSkippedBooleanOperands
def value() -> Bool: return False and missing
