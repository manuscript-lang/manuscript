// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/pipeline_test.go:48 TestPipelineChecksSkippedBooleanOperands
fn value() Bool => return true or 3
// expect-error: MS3000 4:32 logical operands require Bool, found Bool and Int; compare explicitly, e.g. x != 0
