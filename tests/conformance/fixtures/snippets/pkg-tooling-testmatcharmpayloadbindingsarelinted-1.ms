# conform: tags=diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:105 TestMatchArmPayloadBindingsAreLinted
def parse(text: String) -> Result[Int, Error]:
    return ok(1)
