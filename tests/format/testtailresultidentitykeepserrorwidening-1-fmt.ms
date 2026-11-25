// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening

fn tail(value Int!Error) Int! {
	output := value.clone()?
	return ok(output)
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn tail(value Int!) Int! {
// expect-formatted: \toutput := value.clone()?
// expect-formatted: \treturn ok(output)
// expect-formatted: }
