# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/pipeline_test.go:48 TestPipelineChecksSkippedBooleanOperands
def value() -> Bool: return True or 3
