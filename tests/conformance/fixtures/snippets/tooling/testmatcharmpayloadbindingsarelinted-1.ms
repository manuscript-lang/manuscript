// conform: tags=diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:105 TestMatchArmPayloadBindingsAreLinted
fn parse(text String) Int! {
	return ok(1)
}
// expect-exit: 0
