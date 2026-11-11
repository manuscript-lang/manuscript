// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening

fn tail(value: Int!Error) Int!:
	output := value?
	return ok(output)
