// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/pipeline_test.go:16 TestPipelinePreservesCheckedSourceForTools
fn value(flag Bool = not false) Bool {
	callback := fn() Bool => return not (false or false)
	return (not false and callback()) or flag
}
// expect-exit: 0
