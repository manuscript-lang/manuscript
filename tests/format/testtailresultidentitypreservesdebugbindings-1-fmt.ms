// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/result_tail_test.go:39 TestTailResultIdentityPreservesDebugBindings

fn tail(value Int!Error) Int!Error {
	output := value.clone()?
	return ok(output)
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn tail(value Int!) Int! {
// expect-formatted: \toutput := value.clone()?
// expect-formatted: \treturn ok(output)
// expect-formatted: }
