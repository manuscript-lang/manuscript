# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:106 TestMatchArmPayloadBindingsAreLinted
fn answer() Int:
    match parse("1"):
        ok(value): return 1
        error(e): return 2
