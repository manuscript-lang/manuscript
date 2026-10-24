# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/pipeline_test.go:48 TestPipelineChecksSkippedBooleanOperands
def value() -> Bool: return True or 3
