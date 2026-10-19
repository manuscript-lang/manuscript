# conform: tags=formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:105 TestMatchArmPayloadBindingsAreLinted
fn parse(text: String) Result[Int, Error]:
    return ok(1)
