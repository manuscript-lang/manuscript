// conform: tags=control-flow,formatter,tier-core
// conform: phase=run,parse
// conform: origin=pkg/compiler/pipeline_test.go:58 TestSourceAndFileUseTheSamePipeline
export fn main() Int {
	if not false { return 3 }
	return 0
}
