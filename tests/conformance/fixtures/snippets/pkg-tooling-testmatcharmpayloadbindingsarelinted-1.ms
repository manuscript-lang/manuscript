# conform: tags=diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:105 TestMatchArmPayloadBindingsAreLinted
fn parse(text: String) Result[Int, Error]:
    return ok(1)
