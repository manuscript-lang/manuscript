// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/pipeline_test.go:47 TestPipelineChecksSkippedBooleanOperands
fn value() Bool => return false and missing
// expect-error: MS2001 4:37 unknown binding missing; declare it with 'missing := ...' before use, define 'fn missing(...) T { ... }', or import it from a module
